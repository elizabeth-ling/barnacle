import Foundation

/// Ashby public job-board API (§4).
///
/// `https://api.ashbyhq.com/posting-api/job-board/{token}`
///
/// The `{token}` is the board name in `jobs.ashbyhq.com/{token}`, parsed at company-add
/// time (spec `03`). An unknown board answers 404, so a typo'd URL surfaces as
/// `unreachable` in the Add-Company modal rather than as a silently empty board.
struct AshbyAdapter: ATSAdapter {
    static func matches(url: URL) -> Bool {
        (url.host ?? "").lowercased().contains("ashbyhq.com")
    }

    func fetchInternships(for company: CompanySnapshot) async throws -> [ScrapedJob] {
        guard let token = company.atsToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ScrapeError.missingToken(.ashby)
        }
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        guard let url = URL(string: "https://api.ashbyhq.com/posting-api/job-board/\(encoded)") else {
            throw ScrapeError.invalidEndpoint(token)
        }

        let payload = try await fetchJSON(Payload.self, from: url)

        return payload.jobs
            .map { job in
                ScrapedJob(
                    rawID: job.id,
                    title: job.title,
                    // `jobUrl` is the posting page; `applyUrl` is the form inside it. The Feed
                    // opens the posting so the user reads it before applying.
                    url: job.jobUrl ?? job.applyUrl ?? "",
                    datePosted: ISO8601Date.parse(job.publishedAt),
                    location: job.location,
                    // Ashby is the only ATS in §4 that states the country outright, so we take
                    // it and let `LocationClassifier` prefer it over any guess made from the
                    // text (spec `07`). Secondary locations count: a posting listed in both
                    // Toronto and Bengaluru is one the user should see.
                    structuredCountries: job.countries,
                    isRemote: job.isRemote ?? false
                )
            }
            .filter { !$0.url.isEmpty }
    }

    // MARK: - Wire format

    private struct Payload: Decodable {
        let jobs: [Job]

        struct Job: Decodable {
            /// Ashby job ids are UUID strings, already the right shape for `ScrapedJob.rawID`.
            let id: String
            let title: String
            let location: String?
            /// Internet date-time with fractional seconds (`2025-08-07T20:49:38.961+00:00`).
            let publishedAt: String?
            let jobUrl: String?
            let applyUrl: String?
            let isRemote: Bool?
            let address: Address?
            let secondaryLocations: [SecondaryLocation]?

            /// Every country this posting names, primary first. Free of duplicates so a
            /// three-office posting in one country doesn't look like three.
            var countries: [String] {
                var candidates: [String?] = [address?.country]
                candidates.append(contentsOf: (secondaryLocations ?? []).map { $0.address?.country })

                var seen: [String] = []
                for candidate in candidates {
                    guard let candidate, !candidate.isEmpty, !seen.contains(candidate) else { continue }
                    seen.append(candidate)
                }
                return seen
            }

            struct SecondaryLocation: Decodable {
                let address: Address?
            }

            /// `{ "postalAddress": { "addressCountry": "United States", ... } }`. Only the
            /// country is decoded — spec `07` is country-level and says so on purpose.
            struct Address: Decodable {
                let postalAddress: PostalAddress?

                var country: String? { postalAddress?.addressCountry }

                struct PostalAddress: Decodable {
                    let addressCountry: String?
                }
            }
        }

        // Jobs also carry `isListed`. We deliberately don't filter on it: an unlisted posting
        // is still a real opening with a working URL, and dropping it would silently hide an
        // internship the user is tracking the company for.
    }
}
