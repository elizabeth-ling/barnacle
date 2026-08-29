import Foundation

/// One source of internship postings (§4).
///
/// Implementations are stateless value types: they fetch, filter with `InternshipFilter`,
/// and map to `ScrapedJob`. Storage, dedup, and scheduling all live in `ScrapeRunner`.
protocol ATSAdapter: Sendable {
    /// Whether this adapter handles the given careers URL. Used by detection (spec `03`).
    static func matches(url: URL) -> Bool

    /// The company's current internship postings, already filtered by `InternshipFilter`.
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

/// Maps a detected ATS to the adapter that speaks its API.
///
/// Ashby, SmartRecruiters, Workday, and the generic HTML fallback return nil until their
/// adapters land — the scrape loop records that as a per-company failure and keeps going.
enum ATSAdapterRegistry {
    static func adapter(for atsType: ATSType) -> ATSAdapter? {
        switch atsType {
        case .greenhouse: GreenhouseAdapter()
        case .lever: LeverAdapter()
        case .ashby, .smartRecruiters, .workday, .generic: nil
        }
    }
}

enum ScrapeError: LocalizedError, Equatable {
    /// Detection (spec `03`) should always set a token for a token-based ATS.
    case missingToken(ATSType)
    case invalidEndpoint(String)
    case httpFailure(statusCode: Int, url: URL)
    case unsupportedATS(ATSType)

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
        }
    }
}
