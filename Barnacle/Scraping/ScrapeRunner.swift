import Foundation
import OSLog
import SwiftData

/// Runs one scrape pass on its own `ModelContext`, off the main thread (spec `01`).
///
/// `@ModelActor` gives this actor a context bound to its own executor, so fetching,
/// inserting, and saving all happen away from the main actor. Saves are merged into the
/// main context by SwiftData, which is what refreshes the Feed's `@Query` reactively.
@ModelActor
actor ScrapeRunner {
    /// Politeness delay between companies (§7). Only applied *between* companies.
    private static let betweenCompaniesDelay: ClosedRange<Double> = 1...2

    /// Scrapes every active company in turn, storing only what `filter` admits.
    ///
    /// The filter is passed in rather than read here so one pass can't half-apply a settings
    /// change made while it runs (spec `07`).
    ///
    /// Never throws: a company that fails is logged and recorded in `ScrapeRun.failures`,
    /// and the run continues with the next one. The coordinator serializes calls, so this
    /// is never re-entered while a run is in flight.
    func scrapeAll(filter: ScrapeFilter) async -> ScrapeRun {
        let startedAt = Date()
        let companies = activeCompanies()

        var newPostings: [NewPosting] = []
        var failures: [ScrapeFailure] = []

        for (index, company) in companies.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: .seconds(Double.random(in: Self.betweenCompaniesDelay)))
            }

            let name = company.name
            do {
                let fresh = try await scrape(company, filter: filter)
                newPostings.append(contentsOf: fresh)
                ScrapeLog.logger.info("Scraped \(name, privacy: .public): \(fresh.count) new")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append(ScrapeFailure(companyName: name, message: message))
                ScrapeLog.logger.error("Scrape failed for \(name, privacy: .public): \(message, privacy: .public)")
            }
        }

        return ScrapeRun(
            startedAt: startedAt,
            finishedAt: Date(),
            companiesScraped: companies.count,
            newPostings: newPostings.sorted { $0.effectiveDate > $1.effectiveDate },
            failures: failures
        )
    }

    // MARK: - One company

    private func activeCompanies() -> [Company] {
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            ScrapeLog.logger.error("Couldn't fetch companies: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches, dedups, inserts, and saves for one company. Returns only genuinely new
    /// postings — and only once the save succeeded, so we never notify about a posting we
    /// failed to store.
    private func scrape(_ company: Company, filter: ScrapeFilter) async throws -> [NewPosting] {
        guard let adapter = ATSAdapterRegistry.adapter(for: company.atsType) else {
            throw ScrapeError.unsupportedATS(company.atsType)
        }

        let snapshot = CompanySnapshot(company)
        let scraped = try await adapter.fetchInternships(for: snapshot)
        let now = Date()

        var fresh: [NewPosting] = []
        var seenRawIDs: Set<String> = []

        for job in scraped where !job.rawID.isEmpty {
            // Guards against a source listing the same id twice in one payload. Recorded
            // *before* the filter: `seenRawIDs` is what the source listed, and reconciliation
            // must not read "no longer matches your settings" as "gone from the board."
            guard seenRawIDs.insert(job.rawID).inserted else { continue }

            // Spec `07`: the one place role level and location are applied. Filtering at scrape
            // time rather than read time means nothing unwanted is ever stored, so the Feed,
            // the notifier, and anything added later are correct by construction.
            guard filter.admits(title: job.title) else { continue }
            let location = LocationClassifier.classify(
                job.location,
                structuredCountries: job.structuredCountries,
                isRemote: job.isRemote
            )
            guard filter.admits(location) else { continue }

            guard try !isStored(companyID: snapshot.id, rawID: job.rawID) else { continue }

            let posting = JobPosting(
                companyID: snapshot.id,
                companyName: snapshot.name,
                title: job.title,
                url: job.url,
                datePosted: job.datePosted,
                dateFirstSeen: now,
                location: job.location,
                countryCode: location.primaryCountry(preferring: filter.countries),
                isRemote: location.isRemote,
                roleLevel: filter.roleLevel.rawValue,
                rawID: job.rawID
            )
            modelContext.insert(posting)
            fresh.append(
                NewPosting(
                    id: posting.id,
                    companyName: posting.companyName,
                    title: posting.title,
                    url: posting.url,
                    effectiveDate: posting.effectiveDate,
                    location: posting.location
                )
            )
        }

        reconcileClosed(companyID: snapshot.id, stillListed: seenRawIDs, now: now)
        company.lastScrapedAt = now
        try modelContext.save()

        return fresh
    }

    /// The dedup half of §5: a posting is new only if nothing stored shares its
    /// `(companyID, rawID)` pair.
    private func isStored(companyID: UUID, rawID: String) throws -> Bool {
        var descriptor = FetchDescriptor<JobPosting>(
            predicate: JobPosting.existsPredicate(companyID: companyID, rawID: rawID)
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetchCount(descriptor) > 0
    }

    /// Postings are never deleted here (§5) — one that has dropped off the source is stamped
    /// `closedAt` instead, and un-stamped if it comes back. Only runs after a successful
    /// fetch, so a network error can't mass-close a company's postings.
    ///
    /// `stillListed` is everything the source listed, filter or no filter (spec `07`), so a
    /// posting the user's settings now exclude isn't reported as closed.
    private func reconcileClosed(companyID: UUID, stillListed: Set<String>, now: Date) {
        let descriptor = FetchDescriptor<JobPosting>(
            predicate: #Predicate { $0.companyID == companyID }
        )
        guard let stored = try? modelContext.fetch(descriptor) else { return }

        for posting in stored {
            if stillListed.contains(posting.rawID) {
                posting.closedAt = nil
            } else if posting.closedAt == nil {
                posting.closedAt = now
            }
        }
    }
}

extension ScrapeRunner {
    /// One-time backfill for postings stored before spec `07` (guarded by the coordinator's
    /// `scrape.didBackfillRegions` flag): they have a `location` string but no `countryCode`.
    ///
    /// Classifies and stamps only. It never deletes — a purge is something the user asks for in
    /// Settings and confirms, never something a launch does behind their back.
    func backfillRegions() -> Int {
        let descriptor = FetchDescriptor<JobPosting>()
        guard let stored = try? modelContext.fetch(descriptor) else { return 0 }

        var stamped = 0
        for posting in stored where posting.countryCode == nil && posting.roleLevel == nil {
            let match = LocationClassifier.classify(posting.location)
            posting.countryCode = match.primaryCountry(preferring: [])
            posting.isRemote = match.isRemote
            // Whichever level the title reads as, rather than whichever is selected now: these
            // rows predate the setting, and every one of them was stored as an internship.
            posting.roleLevel = RoleLevel.allCases
                .first { RoleLevelFilter.matches(title: posting.title, level: $0) }?
                .rawValue
            stamped += 1
        }

        if stamped > 0 {
            try? modelContext.save()
        }
        return stamped
    }
}

private extension CompanySnapshot {
    /// Taken inside the actor so the adapter never touches the live SwiftData model.
    init(_ company: Company) {
        self.init(
            id: company.id,
            name: company.name,
            atsType: company.atsType,
            atsToken: company.atsToken,
            careerURLs: company.careerURLs
        )
    }
}
