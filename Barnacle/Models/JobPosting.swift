import Foundation
import SwiftData

/// A posting scraped from a company's careers source.
///
/// Only postings that pass the user's settings are ever stored — `ScrapeRunner` applies
/// `RoleLevelFilter` and `LocationClassifier` before inserting (spec `07`), so a role the user
/// isn't looking for, or one in a country they aren't watching, never reaches the database.
@Model
final class JobPosting {
    var id: UUID = UUID()

    /// FK to `Company.id`. Not a SwiftData relationship: postings outlive nothing here,
    /// and the flat id keeps the dedup query cheap.
    var companyID: UUID = UUID()

    /// Denormalized so the feed list renders without touching `Company`.
    var companyName: String = ""

    var title: String = ""

    /// Direct link to the posting. Opened in the browser on click.
    var url: String = ""

    /// From the ATS when it exposes one (Greenhouse `updated_at`, Lever `createdAt`, …).
    /// Nil when the source doesn't say.
    var datePosted: Date?

    /// When our scraper first saw this posting. Always set; the fallback for `datePosted`.
    var dateFirstSeen: Date = Date()

    var location: String?

    /// The country `LocationClassifier` resolved for this posting, ISO 3166-1 alpha-2 (spec
    /// `07`). Nil means the location didn't resolve — unknown, not "nowhere" — which is why the
    /// row still shows the raw `location` string for the user to judge.
    var countryCode: String?

    /// Whether the source called this posting remote. Defaults false.
    var isRemote: Bool = false

    /// The `RoleLevel` that admitted this posting, as its raw value. Informational: the purge
    /// re-reads the title rather than trusting this, so a keyword-list change can't strand a row.
    var roleLevel: String?

    /// The ATS's own job id. Half of the dedup key — see `isDuplicate(of:)`.
    var rawID: String = ""

    /// Set when the posting stops appearing at the source. We never delete postings —
    /// the user may still want the record (§5).
    var closedAt: Date?

    /// When the user opened this posting from the feed. Nil until they click the row, which
    /// is what clears its NEW badge (spec `02`). Optional, so it migrates in place.
    var viewedAt: Date?

    /// When the user dismissed this posting from the feed (spec `02`). Nil for everything they
    /// haven't ruled out, which is the ordinary feed.
    ///
    /// A dismissal hides the row; it never deletes it. Deleting would fight the scrape loop —
    /// dedup is `(companyID, rawID)`, so the next run would re-insert the posting and notify
    /// about it again. Independent of `closedAt`: the source reopening a posting must not undo
    /// a decision the user made.
    var dismissedAt: Date?

    init(
        id: UUID = UUID(),
        companyID: UUID,
        companyName: String,
        title: String,
        url: String,
        datePosted: Date? = nil,
        dateFirstSeen: Date = Date(),
        location: String? = nil,
        countryCode: String? = nil,
        isRemote: Bool = false,
        roleLevel: String? = nil,
        rawID: String,
        closedAt: Date? = nil,
        viewedAt: Date? = nil,
        dismissedAt: Date? = nil
    ) {
        self.id = id
        self.companyID = companyID
        self.companyName = companyName
        self.title = title
        self.url = url
        self.datePosted = datePosted
        self.dateFirstSeen = dateFirstSeen
        self.location = location
        self.countryCode = countryCode
        self.isRemote = isRemote
        self.roleLevel = roleLevel
        self.rawID = rawID
        self.closedAt = closedAt
        self.viewedAt = viewedAt
        self.dismissedAt = dismissedAt
    }

    /// The date used for display and sorting everywhere in the app (§5).
    var effectiveDate: Date {
        datePosted ?? dateFirstSeen
    }

    /// True once the posting has disappeared from its source.
    var isClosed: Bool {
        closedAt != nil
    }

    /// Drives the feed's NEW badge (spec `02`).
    ///
    /// The spec words this as "first seen in the last 24h *or* not yet viewed," but those two
    /// clauses fight each other: a posting scraped an hour ago and then clicked would still be
    /// inside its 24h window, while the spec also requires the click to clear the badge. Unviewed
    /// is the clause that survives — a posting first seen in the last 24h is unviewed anyway,
    /// unless the user already opened it, and then the badge must be gone.
    var isUnviewed: Bool {
        viewedAt == nil
    }

    /// True once the user has dismissed the posting, which is what keeps it out of the feed.
    var isDismissed: Bool {
        dismissedAt != nil
    }
}

extension JobPosting {
    /// Dedup key (§5): a scraped posting is *new* if nothing stored shares this pair.
    ///
    /// SwiftData can only enforce single-property uniqueness on macOS 14 (compound
    /// `#Unique` is macOS 15+), so the scrape loop enforces this in code via `existsPredicate`.
    static func existsPredicate(companyID: UUID, rawID: String) -> Predicate<JobPosting> {
        #Predicate<JobPosting> { posting in
            posting.companyID == companyID && posting.rawID == rawID
        }
    }
}
