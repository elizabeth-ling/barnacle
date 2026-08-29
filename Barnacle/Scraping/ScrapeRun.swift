import Foundation
import OSLog

/// What one pass over every active company produced.
struct ScrapeRun: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let companiesScraped: Int

    /// Every posting inserted during this run, newest first. Handed to the notifier as a
    /// single batch so one run means at most one notification (spec `04`).
    let newPostings: [NewPosting]

    /// Companies that failed. One failure never stops the rest of the run.
    let failures: [ScrapeFailure]

    static func empty(at date: Date = Date()) -> ScrapeRun {
        ScrapeRun(startedAt: date, finishedAt: date, companiesScraped: 0, newPostings: [], failures: [])
    }
}

/// A posting seen for the first time in this run, as a value the notifier can carry across
/// actors (the stored `JobPosting` belongs to the scrape context and can't leave it).
struct NewPosting: Sendable, Identifiable, Equatable {
    let id: UUID
    let companyName: String
    let title: String
    let url: String
    let effectiveDate: Date
    let location: String?
}

struct ScrapeFailure: Sendable, Equatable {
    let companyName: String
    let message: String
}

enum ScrapeLog {
    static let logger = Logger(subsystem: "com.elizabeth.barnacle", category: "scrape")
}
