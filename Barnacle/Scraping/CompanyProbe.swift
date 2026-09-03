import Foundation

/// One job board that answered to a typed company name (spec `08`).
struct CompanyBoard: Sendable, Equatable, Identifiable {
    let atsType: ATSType

    /// The slug that answered — which is also the board token.
    let slug: String

    /// The careers URL this board lives at, written in the form `ATSDetector` already
    /// classifies. Handed to `CompanyURLChecker` untouched (spec `08`, "Reuse, don't rebuild").
    let boardURL: String

    /// How many of the board's postings match the user's spec-`07` settings — the count the
    /// user would actually receive, not the board's headcount.
    let matchingRoles: Int

    var id: String { "\(atsType.rawValue)|\(slug)" }
}

/// Finds a company's job board from its **name** (spec `08`).
///
/// Greenhouse, Lever, and Ashby publish no company search endpoint — there is no directory to
/// query — so this is probing, not search. It works because a board token is almost always the
/// company name lowercased and de-spaced: eight of eight sampled companies resolved that way.
enum CompanyProbe {
    /// The ATSes with both a token-shaped URL and a working adapter. SmartRecruiters and
    /// Workday are left out until their adapters land: a hit we can't fetch would be a row with
    /// no role count, which is the one thing that disambiguates two boards.
    static let probedTypes: [ATSType] = [.greenhouse, .lever, .ashby]

    /// The same short budget the modal already gives detection. This blocks a modal, so it
    /// can't wait on the scrape timeout — and every probe runs in parallel, so this is the
    /// whole wait rather than the wait per board.
    static let timeout: TimeInterval = 15

    /// The slugs to try for a typed name, most likely first.
    ///
    /// `"Scale AI"` → `["scaleai", "scale-ai"]`, `"Match Group"` → `["matchgroup",
    /// "match-group"]`. The hyphenated variant is there because some boards use it; a
    /// single-word name produces just the one slug.
    static func slugs(for name: String) -> [String] {
        let folded = name
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let words = folded.split { !Self.slugCharacters.contains($0) }.map(String.init)
        guard !words.isEmpty else { return [] }

        let compact = words.joined()
        let hyphenated = words.joined(separator: "-")
        return compact == hyphenated ? [compact] : [compact, hyphenated]
    }

    /// The careers URL for a board, in the shape a user would recognize and detection parses.
    static func boardURL(atsType: ATSType, slug: String) -> String? {
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        switch atsType {
        case .greenhouse: return "https://boards.greenhouse.io/\(encoded)"
        case .lever: return "https://jobs.lever.co/\(encoded)"
        case .ashby: return "https://jobs.ashbyhq.com/\(encoded)"
        case .smartRecruiters, .workday, .generic: return nil
        }
    }

    /// Probes every ATS for every slug **in parallel** and returns the boards that answered.
    ///
    /// Sorted by role count so the liveliest board leads: `vercel` genuinely answers on both
    /// Greenhouse and Ashby, and a stale board usually reports zero.
    static func probe(
        name: String,
        filter: ScrapeFilter = .stored(),
        timeout: TimeInterval = CompanyProbe.timeout
    ) async -> [CompanyBoard] {
        let slugs = slugs(for: name)
        guard !slugs.isEmpty else { return [] }

        let found = await withTaskGroup(of: CompanyBoard?.self) { group -> [CompanyBoard] in
            for atsType in probedTypes {
                for slug in slugs {
                    group.addTask {
                        await probeOne(atsType: atsType, slug: slug, filter: filter, timeout: timeout)
                    }
                }
            }

            var boards: [CompanyBoard] = []
            for await board in group {
                if let board { boards.append(board) }
            }
            return boards
        }

        return rank(found, slugs: slugs)
    }

    // MARK: - One board

    private static func probeOne(
        atsType: ATSType,
        slug: String,
        filter: ScrapeFilter,
        timeout: TimeInterval
    ) async -> CompanyBoard? {
        guard let boardURL = boardURL(atsType: atsType, slug: slug),
              let adapter = ATSAdapterRegistry.adapter(for: atsType) else { return nil }

        // A board that doesn't exist answers 404, which is exactly the miss we want: the
        // adapter throwing *is* the negative result.
        let snapshot = CompanySnapshot(
            id: UUID(),
            name: slug,
            atsType: atsType,
            atsToken: slug,
            careerURLs: [boardURL]
        )
        guard let jobs = try? await withDeadline(timeout, operation: {
            try await adapter.fetchInternships(for: snapshot)
        }) else { return nil }

        return CompanyBoard(
            atsType: atsType,
            slug: slug,
            boardURL: boardURL,
            matchingRoles: jobs.filter { filter.admits($0) }.count
        )
    }

    /// One row per ATS, best hit first.
    ///
    /// Both slug variants can answer on the same ATS (a board reachable as `scaleai` and
    /// `scale-ai`), and showing the user the same company twice with the same ATS is a choice
    /// with no meaning. Keep the richer of the two, breaking ties towards the first slug tried.
    private static func rank(_ boards: [CompanyBoard], slugs: [String]) -> [CompanyBoard] {
        var best: [ATSType: CompanyBoard] = [:]
        for board in boards {
            guard let incumbent = best[board.atsType] else {
                best[board.atsType] = board
                continue
            }
            let slugRank = slugs.firstIndex(of: board.slug) ?? slugs.count
            let incumbentRank = slugs.firstIndex(of: incumbent.slug) ?? slugs.count
            if (board.matchingRoles, -slugRank) > (incumbent.matchingRoles, -incumbentRank) {
                best[board.atsType] = board
            }
        }

        return best.values.sorted { lhs, rhs in
            if lhs.matchingRoles != rhs.matchingRoles { return lhs.matchingRoles > rhs.matchingRoles }
            let lhsRank = probedTypes.firstIndex(of: lhs.atsType) ?? probedTypes.count
            let rhsRank = probedTypes.firstIndex(of: rhs.atsType) ?? probedTypes.count
            return lhsRank < rhsRank
        }
    }

    // MARK: - Deadline

    private struct ProbeTimeout: Error {}

    /// Runs `operation` with a hard deadline, cancelling it when the deadline wins.
    ///
    /// The adapters fix their own request timeout at the scrape budget, so bounding them here
    /// is what keeps the modal from hanging on a board that accepts the connection and then
    /// says nothing.
    private static func withDeadline<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ProbeTimeout()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw ProbeTimeout() }
            return result
        }
    }

    private static let slugCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789")
}
