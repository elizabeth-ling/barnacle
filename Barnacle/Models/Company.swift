import Foundation
import SwiftData

/// A company the user has explicitly chosen to track.
///
/// Companies are only ever added by hand (§1 non-goals: this is not a job aggregator).
@Model
final class Company {
    var id: UUID = UUID()

    /// Display name as the user typed it.
    var name: String = ""

    /// One or more careers pages. Usually one.
    var careerURLs: [String] = []

    /// Set by adapter detection (spec `03`).
    var atsType: ATSType = ATSType.generic

    /// Board token parsed out of the careers URL — e.g. the `{token}` in
    /// `boards.greenhouse.io/{token}`. Nil for `generic`, where there's nothing to parse.
    var atsToken: String?

    /// Inactive companies are skipped during the scrape loop (§7).
    var isActive: Bool = true

    var dateAdded: Date = Date()

    /// Last successful scrape, for display and debugging (§7). Nil until first scraped.
    var lastScrapedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        careerURLs: [String],
        atsType: ATSType,
        atsToken: String? = nil,
        isActive: Bool = true,
        dateAdded: Date = Date(),
        lastScrapedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.careerURLs = careerURLs
        self.atsType = atsType
        self.atsToken = atsToken
        self.isActive = isActive
        self.dateAdded = dateAdded
        self.lastScrapedAt = lastScrapedAt
    }
}
