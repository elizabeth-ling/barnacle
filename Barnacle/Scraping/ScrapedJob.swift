import Foundation

/// One posting as an ATS reports it, before it becomes a stored `JobPosting`.
///
/// Adapters return these and nothing else — they never touch storage (spec `01`).
struct ScrapedJob: Sendable, Equatable {
    /// The ATS's own job id. Required: half of the `(companyID, rawID)` dedup key (§5).
    let rawID: String

    let title: String

    /// Direct link to the posting.
    let url: String

    /// Nil when the ATS doesn't expose one — the stored posting then falls back to
    /// `dateFirstSeen` via `JobPosting.effectiveDate`.
    let datePosted: Date?

    let location: String?
}
