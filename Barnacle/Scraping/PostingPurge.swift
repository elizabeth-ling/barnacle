import Foundation
import SwiftData

/// Deletes the stored postings a settings change has made irrelevant (spec `07`).
///
/// §5 says "don't delete them — the user may still want the record," and spec `07` deviates on
/// purpose: a posting is worth applying to for about two days, so a closed internship listing
/// after graduation is worth nothing.
///
/// **Why deleting is safe here and nowhere else.** Dedup is `(companyID, rawID)`, so a deleted
/// posting that is still listed at the source comes back on the next run — and gets notified
/// about a second time. That's why spec `02`'s dismissal marks `dismissedAt` instead. A settings
/// purge escapes the trap for one specific reason: **the purge criterion and the new filter
/// criterion are the same**, so what this deletes, `ScrapeRunner` now rejects on the way in.
/// Only ever delete when those two agree.
enum PostingPurge {
    /// Postings the given settings would no longer admit.
    static func unmatched(_ postings: [JobPosting], under filter: ScrapeFilter) -> [JobPosting] {
        postings.filter { isUnmatched($0, under: filter) }
    }

    /// Deletes them and returns how many went.
    @discardableResult
    static func purge(
        _ postings: [JobPosting],
        under filter: ScrapeFilter,
        in context: ModelContext
    ) -> Int {
        let doomed = unmatched(postings, under: filter)
        for posting in doomed {
            context.delete(posting)
        }
        return doomed.count
    }

    static func isUnmatched(_ posting: JobPosting, under filter: ScrapeFilter) -> Bool {
        if !filter.admits(title: posting.title) { return true }

        let match = location(of: posting)
        // **Unknown-location postings are never purged**, whatever `includeUnknownLocation`
        // says. That switch shapes what future scrapes store; a posting already on screen, with
        // its raw location visible for the user to judge, is not something to delete over an
        // ambiguity. Deleting is the one destructive act in the app, so it only ever fires on a
        // location that resolved and landed outside the allowed set.
        guard !match.hasUnknown, !filter.countries.isEmpty else { return false }
        return match.countries.isDisjoint(with: filter.countries)
    }

    /// Where a stored posting is, re-derived rather than trusted.
    ///
    /// The text is reclassified and the stored `countryCode` is added to what it found, rather
    /// than replacing it: a posting listed in "Dublin; Bengaluru, India" stored `IN`, and
    /// treating that lone code as the whole answer would lose the unknown half and delete it.
    static func location(of posting: JobPosting) -> LocationClassifier.Match {
        var match = LocationClassifier.classify(posting.location, isRemote: posting.isRemote)
        if let code = posting.countryCode {
            match.countries.insert(code)
        }
        return match
    }
}
