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
        let parseDate = Self.makeDateParser()

        return payload.jobs
            .filter { InternshipFilter.isInternship(title: $0.title) }
            .map { job in
                ScrapedJob(
                    rawID: String(job.id),
                    title: job.title,
                    url: job.absoluteURL,
                    datePosted: parseDate(job.updatedAt),
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

    /// Greenhouse sends internet date-time (`2026-08-25T17:40:40-04:00`), occasionally with
    /// fractional seconds. An unparseable date is nil rather than fatal: the posting still
    /// counts, it just falls back to `dateFirstSeen` (§5).
    private static func makeDateParser() -> (String?) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return { raw in
            guard let raw, !raw.isEmpty else { return nil }
            return plain.date(from: raw) ?? fractional.date(from: raw)
        }
    }
}
