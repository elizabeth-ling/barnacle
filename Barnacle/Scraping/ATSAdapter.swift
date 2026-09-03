import Foundation

/// One source of postings (§4).
///
/// Implementations are stateless value types: they fetch and map to `ScrapedJob`. Storage,
/// dedup, filtering, and scheduling all live in `ScrapeRunner`.
protocol ATSAdapter: Sendable {
    /// Whether this adapter handles the given careers URL. Used by detection (spec `03`).
    static func matches(url: URL) -> Bool

    /// Everything the source currently lists for this company.
    ///
    /// - Important: **do not filter here.** Spec `07` moved role level and location into
    ///   `ScrapeRunner` so the rule lives in one place and `reconcileClosed` can still tell
    ///   "gone from the source" from "no longer matches your settings." The name is §4's and
    ///   predates that move. Returning less than the source lists would close stored postings
    ///   that are still open.
    func fetchInternships(for company: CompanySnapshot) async throws -> [ScrapedJob]
}

extension ATSAdapter {
    /// Shared GET-and-decode used by the JSON adapters.
    func fetchJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ScrapeError.httpFailure(statusCode: http.statusCode, url: url)
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// One HTML GET, shared by adapter-detection (spec `03`) and the generic adapter.
///
/// Separate from `fetchJSON` because the callers want different timeouts: detection blocks a
/// modal and gives up quickly, while a scrape run can afford to wait.
enum PageFetch {
    static func html(at url: URL, timeout: TimeInterval = 30) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ScrapeError.httpFailure(statusCode: http.statusCode, url: url)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Internet date-time parsing shared by the JSON adapters.
///
/// ATSes disagree about fractional seconds — Greenhouse usually omits them, Ashby always
/// sends them — so try both. An unparseable date is nil rather than fatal: the posting
/// still counts, it just falls back to `dateFirstSeen` (§5).
enum ISO8601Date {
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return plain.date(from: raw) ?? fractional.date(from: raw)
    }
}

/// Maps a detected ATS to the adapter that speaks its API.
///
/// SmartRecruiters and Workday return nil until their adapters land — the scrape loop
/// records that as a per-company failure and keeps going.
enum ATSAdapterRegistry {
    static func adapter(for atsType: ATSType) -> ATSAdapter? {
        switch atsType {
        case .greenhouse: GreenhouseAdapter()
        case .lever: LeverAdapter()
        case .ashby: AshbyAdapter()
        case .generic: GenericAdapter()
        case .smartRecruiters, .workday: nil
        }
    }
}

enum ScrapeError: LocalizedError, Equatable {
    /// Detection (spec `03`) should always set a token for a token-based ATS.
    case missingToken(ATSType)
    case invalidEndpoint(String)
    case httpFailure(statusCode: Int, url: URL)
    case unsupportedATS(ATSType)
    case noCareerURLs
    case unreadablePage(url: String)

    var errorDescription: String? {
        switch self {
        case .missingToken(let ats):
            "No \(ats.displayName) board token stored for this company."
        case .invalidEndpoint(let token):
            "Couldn't build a valid endpoint URL from the token “\(token)”."
        case .httpFailure(let statusCode, let url):
            "HTTP \(statusCode) from \(url.absoluteString)."
        case .unsupportedATS(let ats):
            "No adapter for \(ats.displayName) yet."
        case .noCareerURLs:
            "This company has no careers URL to read."
        case .unreadablePage(let url):
            "Couldn\u{2019}t read the page at \(url)."
        }
    }
}
