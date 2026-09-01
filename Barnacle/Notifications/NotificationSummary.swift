import Foundation

/// Turns one scrape run's batch of new postings into the title and body both the native
/// notification and the ntfy push use (spec `04` asks for the same summary text on both).
///
/// Pure string building, deliberately separate from `NotificationService`: it's the part with
/// edge cases worth reading at a glance (one posting vs. many, the "and N more" tail).
enum NotificationSummary {
    /// Spec: "lists up to ~3 lines, then 'and N more.'"
    static let maxListedPostings = 3

    static func title(for postings: [NewPosting]) -> String {
        if postings.count == 1 {
            return "New internship at \(postings[0].companyName)"
        }
        return "\(postings.count) new internships"
    }

    static func body(for postings: [NewPosting]) -> String {
        if postings.count == 1 {
            return postings[0].title
        }

        var lines = postings.prefix(maxListedPostings).map { "\($0.companyName) \u{2014} \($0.title)" }
        let remaining = postings.count - lines.count
        if remaining > 0 {
            lines.append("and \(remaining) more.")
        }
        return lines.joined(separator: "\n")
    }
}
