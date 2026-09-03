import Foundation

/// Lever postings API (§4).
///
/// `https://api.lever.co/v0/postings/{token}?mode=json`
struct LeverAdapter: ATSAdapter {
    static func matches(url: URL) -> Bool {
        (url.host ?? "").lowercased().contains("lever.co")
    }

    func fetchInternships(for company: CompanySnapshot) async throws -> [ScrapedJob] {
        guard let token = company.atsToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ScrapeError.missingToken(.lever)
        }
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        guard let url = URL(string: "https://api.lever.co/v0/postings/\(encoded)?mode=json") else {
            throw ScrapeError.invalidEndpoint(token)
        }

        let postings = try await fetchJSON([Posting].self, from: url)

        return postings
            .map { posting in
                ScrapedJob(
                    rawID: posting.id,
                    title: posting.text,
                    url: posting.hostedUrl,
                    datePosted: posting.createdAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
                    location: posting.categories?.location
                )
            }
    }

    // MARK: - Wire format

    private struct Posting: Decodable {
        let id: String
        /// Lever calls the job title `text`.
        let text: String
        let hostedUrl: String
        /// Epoch milliseconds.
        let createdAt: Int?
        let categories: Categories?

        struct Categories: Decodable {
            let location: String?
        }
    }
}
