import Foundation
import SwiftSoup

/// The HTML fallback for careers pages that aren't on a known ATS (§4).
///
/// Every other adapter asks an API for a list of jobs. This one has no API to ask, so it
/// inverts the problem: fetch the page and return every link whose text is shaped like a job
/// title. It deliberately does **not** filter by role level — spec `07` moved that to
/// `ScrapeRunner`, so the runner sees everything the page listed and reconciliation can still
/// tell "gone from the page" from "no longer matches your settings."
///
/// **What it deliberately doesn't do:** follow pagination, run JavaScript, or read anything the
/// server didn't render. A board that paginates (Bloomberg's Avature site lists 12 of 363 per
/// page) only exposes its first page here, so the URL stored for the company should be one that
/// lists what you care about — spec `03` lets a company carry several URLs for exactly this.
struct GenericAdapter: ATSAdapter {
    /// The fallback matches anything. Never consulted by `ATSAdapterRegistry` — detection
    /// (spec `03`) decides what's generic, and this is where those companies land.
    static func matches(url: URL) -> Bool { true }

    /// A sanity cap on *links*, not postings: with the role filter gone from here (spec `07`)
    /// this adapter returns every plausible title on the page and lets the runner choose. A
    /// careers page with more than this many is misparsed, not a careers page.
    private static let maxPostings = 1000

    func fetchInternships(for company: CompanySnapshot) async throws -> [ScrapedJob] {
        guard !company.careerURLs.isEmpty else { throw ScrapeError.noCareerURLs }

        var jobs: [ScrapedJob] = []
        var seen: Set<String> = []
        var lastError: Error?
        var readAnyPage = false

        for raw in company.careerURLs {
            guard let url = URL(string: raw) else {
                lastError = ScrapeError.invalidEndpoint(raw)
                continue
            }

            do {
                let html = try await PageFetch.html(at: url)
                readAnyPage = true
                for job in try Self.internships(in: html, pageURL: url) where seen.insert(job.rawID).inserted {
                    jobs.append(job)
                    if jobs.count >= Self.maxPostings { return jobs }
                }
            } catch {
                lastError = error
            }
        }

        // One unreadable URL out of several is survivable; none readable is a failure, so the
        // run records it instead of silently reporting "no internships."
        if !readAnyPage {
            throw lastError ?? ScrapeError.unreadablePage(url: company.careerURLs[0])
        }
        return jobs
    }

    // MARK: - Parsing

    static func internships(in html: String, pageURL: URL) throws -> [ScrapedJob] {
        let document: Document
        do {
            document = try SwiftSoup.parse(html, pageURL.absoluteString)
        } catch {
            throw ScrapeError.unreadablePage(url: pageURL.absoluteString)
        }

        guard let links = try? document.select("a[href]").array() else { return [] }

        var jobs: [ScrapedJob] = []
        var seen: Set<String> = []

        for link in links {
            guard let title = title(of: link), isPlausibleTitle(title),
                  let href = try? link.attr("abs:href"),
                  let resolved = URL(string: href),
                  let scheme = resolved.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { continue }

            // No ATS id exists here, so the posting's own URL is the dedup key (§5). Query and
            // fragment are dropped: session ids and `#apply` anchors would otherwise make the
            // same posting look new on every scrape.
            let rawID = stableID(for: resolved)
            guard seen.insert(rawID).inserted else { continue }

            jobs.append(
                ScrapedJob(
                    rawID: rawID,
                    title: title,
                    url: resolved.absoluteString,
                    // Plain HTML rarely dates a posting reliably; `effectiveDate` falls back to
                    // `dateFirstSeen` (§5), which is the honest answer for a page we just met.
                    datePosted: nil,
                    location: nil
                )
            )
        }

        return jobs
    }

    /// The posting's title as written inside the link.
    ///
    /// Careers pages often wrap an entire posting card in one `<a>`, so the flat text welds the
    /// title to everything beside it — Lever's cards come out as "…, Internship On-site —
    /// Full-timeParis, France". A heading inside the link is the title far more often than not,
    /// so try that, then an element whose class says "title", before falling back to flat text.
    private static func title(of link: Element) -> String? {
        for selector in ["h1, h2, h3, h4, h5, h6", "[class*=title]"] {
            if let candidate = try? link.select(selector).first(),
               let text = try? candidate.text(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let own = link.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }

        return (try? link.text())?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps nav furniture out of the feed.
    ///
    /// The role filter alone would accept an "Internships" menu item, since that's a whole-word
    /// match. Real job titles run to several words; category links are one or two.
    private static func isPlausibleTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 140 else { return false }
        return trimmed.split(whereSeparator: \.isWhitespace).count >= 2
    }

    private static func stableID(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        var id = components?.url?.absoluteString ?? url.absoluteString
        if id.count > 1, id.hasSuffix("/") {
            id.removeLast()
        }
        return id
    }
}
