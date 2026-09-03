import Foundation

/// Greenhouse job board API (§4).
///
/// `https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true`
struct GreenhouseAdapter: ATSAdapter {
    static func matches(url: URL) -> Bool {
        (url.host ?? "").lowercased().contains("greenhouse.io")
    }

    func fetchInternships(for company: CompanySnapshot) async throws -> [ScrapedJob] {
        guard let token = company.atsToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ScrapeError.missingToken(.greenhouse)
        }
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        guard let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(encoded)/jobs?content=true") else {
            throw ScrapeError.invalidEndpoint(token)
        }

        let payload = try await fetchJSON(Payload.self, from: url)

        return payload.jobs
            .map { job in
                ScrapedJob(
                    rawID: String(job.id),
                    title: job.title,
                    url: job.absoluteURL,
                    datePosted: ISO8601Date.parse(job.updatedAt),
                    location: job.location?.name
                )
            }
    }

    // MARK: - Wire format

    private struct Payload: Decodable {
        let jobs: [Job]

        struct Job: Decodable {
            /// Greenhouse job ids are numeric; stringified for `ScrapedJob.rawID`.
            let id: Int
            let title: String
            let absoluteURL: String
            let updatedAt: String?
            let location: Location?

            struct Location: Decodable {
                let name: String?
            }

            enum CodingKeys: String, CodingKey {
                case id, title, location
                case absoluteURL = "absolute_url"
                case updatedAt = "updated_at"
            }
        }
    }
}
