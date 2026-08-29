import Foundation

/// The one place that decides whether a posting is an internship (§6).
///
/// Adapters call this before returning, so non-internship roles are never stored.
enum InternshipFilter {
    /// `intern` alone already catches "intern" and "internship"; the co-op spellings are
    /// listed because some companies use that term instead.
    static let keywords = ["intern", "internship", "co-op", "co op", "coop"]

    static func isInternship(title: String) -> Bool {
        let lowercased = title.lowercased()
        return keywords.contains { lowercased.contains($0) }
    }
}
