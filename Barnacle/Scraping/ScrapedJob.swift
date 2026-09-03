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

    /// Countries the ATS stated outright, when it does (Ashby's structured address). Preferred
    /// over any guess made from `location` — see `LocationClassifier` (spec `07`).
    let structuredCountries: [String]

    /// The ATS's own remote flag, when it has one.
    let isRemote: Bool

    /// Written out rather than left to the memberwise initializer so the adapters that have no
    /// structured location data don't have to say so at every call site.
    init(
        rawID: String,
        title: String,
        url: String,
        datePosted: Date?,
        location: String?,
        structuredCountries: [String] = [],
        isRemote: Bool = false
    ) {
        self.rawID = rawID
        self.title = title
        self.url = url
        self.datePosted = datePosted
        self.location = location
        self.structuredCountries = structuredCountries
        self.isRemote = isRemote
    }
}
