import Foundation

/// One careers URL, classified (spec `03`, "Adapter detection").
struct ATSDetection: Sendable, Equatable {
    let atsType: ATSType

    /// The board token the adapter needs — the `{token}` in `boards.greenhouse.io/{token}`
    /// and friends. Nil for `generic`, where there's nothing to parse.
    let atsToken: String?

    /// The URL after normalization: scheme added if it was missing, host lowercased. This is
    /// what gets stored in `Company.careerURLs`, so what we store is always fetchable.
    let normalizedURL: String

    /// True when we recognized the page as a real ATS rather than falling back.
    var isKnownATS: Bool { atsType != .generic }
}

/// Turns a careers-page URL into an `ATSType` + token, so the scrape engine (spec `01`) knows
/// which adapter to use and what to ask it for.
///
/// Detection is pure and synchronous. The one network step — reclassifying a company's own
/// `/careers` page that merely embeds an ATS — is `detectEmbedded(in:)` fed by `fetchHTML(at:)`,
/// kept separate so the classification rules can be exercised without a network.
enum ATSDetector {
    /// Hosts that carry no board token of their own, so a `{token}.host` reading of them is wrong.
    private static let genericSubdomains: Set<String> = ["www", "careers", "jobs", "api", "job-boards", "boards"]

    /// Classifies one URL. Nil when the text isn't a URL at all — that's never saved.
    static func detect(_ raw: String) -> ATSDetection? {
        guard let (url, host) = normalize(raw) else { return nil }
        let normalized = url.absoluteString
        let segments = url.path.split(separator: "/").map(String.init)

        func detection(_ type: ATSType, _ token: String?) -> ATSDetection {
            ATSDetection(
                atsType: type,
                atsToken: token.flatMap { $0.isEmpty ? nil : $0 },
                normalizedURL: normalized
            )
        }

        if host.hasSuffix("greenhouse.io") {
            return detection(.greenhouse, greenhouseToken(url: url, segments: segments))
        }
        if host.hasSuffix("lever.co") {
            return detection(.lever, segments.first)
        }
        if host.hasSuffix("ashbyhq.com") {
            return detection(.ashby, segments.first)
        }
        if host.hasSuffix("smartrecruiters.com") {
            return detection(.smartRecruiters, smartRecruitersToken(host: host, segments: segments))
        }
        if host.hasSuffix("myworkdayjobs.com") {
            // Workday's CXS endpoint needs the host (which carries the datacenter, e.g. `wd5`),
            // the tenant, *and* the site name, so store the whole normalized URL and leave the
            // parsing to the Workday adapter when its spec lands.
            return detection(.workday, normalized)
        }
        return detection(.generic, nil)
    }

    /// Spec `03` step 3: a company's own careers page often just embeds or links to the real
    /// ATS (a Greenhouse `job_board` script, a "View openings" link to Lever). Scans fetched
    /// HTML for the first URL that classifies as a known ATS *with* a token.
    ///
    /// Nice-to-have by the spec, and treated that way: no match simply leaves the page `generic`.
    static func detectEmbedded(in html: String) -> ATSDetection? {
        let pattern = #"https?://[A-Za-z0-9._~%-]+\.(?:greenhouse\.io|lever\.co|ashbyhq\.com|smartrecruiters\.com|myworkdayjobs\.com)(?:/[^\s"'<>\\)]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let matchRange = Range(match.range, in: html) else { continue }
            // Markup escapes the query separator (`?for=x&amp;b=y`), which would otherwise end
            // up inside the token.
            let candidate = String(html[matchRange]).replacingOccurrences(of: "&amp;", with: "&")
            if let detection = detect(candidate), detection.isKnownATS, detection.atsToken != nil {
                return detection
            }
        }
        return nil
    }

    // MARK: - Normalization

    /// Adds a scheme if the user typed a bare host, lowercases the host, and rejects anything
    /// that isn't recognizably a URL. Returns the rebuilt URL and its lowercased host.
    private static func normalize(_ raw: String) -> (url: URL, host: String)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              // A bare word ("stripe") parses as a host but isn't a careers page.
              host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }

        components.scheme = scheme
        components.host = host
        // A trailing slash would turn the first path segment into an empty string for
        // `host.com/` and add nothing anywhere else.
        if components.path == "/" {
            components.path = ""
        }

        guard let url = components.url else { return nil }
        return (url, host)
    }

    // MARK: - Per-ATS token rules

    /// `boards.greenhouse.io/{token}` and `job-boards.greenhouse.io/{token}`, plus the embed
    /// form `boards.greenhouse.io/embed/job_board?for={token}` that turns up inside company
    /// pages — its first path segment is `embed`, which is not a token.
    private static func greenhouseToken(url: URL, segments: [String]) -> String? {
        if segments.first == "embed" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name.lowercased() == "for" }?
                .value
        }
        return segments.first
    }

    /// Either `{token}.smartrecruiters.com` or `careers.smartrecruiters.com/{token}`.
    private static func smartRecruitersToken(host: String, segments: [String]) -> String? {
        let labels = host.split(separator: ".").map(String.init)
        if labels.count > 2, let subdomain = labels.first, !genericSubdomains.contains(subdomain) {
            return subdomain
        }
        return segments.first
    }
}
