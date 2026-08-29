import Foundation

/// The one place that decides whether a posting is an internship (§6).
///
/// Adapters call this before returning, so non-internship roles are never stored.
enum InternshipFilter {
    /// `intern` alone already catches "intern" and "internship"; the co-op spellings are
    /// listed because some companies use that term instead.
    static let keywords = ["intern", "internship", "co-op", "co op", "coop"]

    /// Keywords match whole words (plus an optional plural `s`), not bare substrings.
    ///
    /// A plain `contains` check reads "Internal Audit Lead" as an internship — real boards
    /// are full of those, and they'd land in the feed and fire notifications. Word
    /// boundaries drop them while still catching "Intern", "Interns", "Internship", and
    /// the co-op spellings.
    static func isInternship(title: String) -> Bool {
        let lowercased = title.lowercased()
        return keywords.contains { keyword in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))s?\\b"
            return lowercased.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
