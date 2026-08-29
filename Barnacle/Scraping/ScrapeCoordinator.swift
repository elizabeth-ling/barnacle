import Foundation
import Observation
import SwiftData

/// Owns *when* scraping happens (§7): once at launch, every 15 minutes ± jitter after that,
/// and whenever the user asks. The work itself belongs to `ScrapeRunner`.
///
/// Main-actor and observable so views can read `isScraping` / `lastRun` directly; the timer
/// lives on this object rather than in a view, so closing the main window doesn't stop it.
@MainActor
@Observable
final class ScrapeCoordinator {
    private(set) var isScraping = false
    private(set) var lastRun: ScrapeRun?

    /// Spec `04` hooks the notifier up here: one call per run, carrying that run's whole
    /// batch of new postings, so a run can only ever produce one notification.
    @ObservationIgnored var onNewPostings: (([NewPosting]) -> Void)?

    @ObservationIgnored private let runner: ScrapeRunner
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    init(container: ModelContainer) {
        runner = ScrapeRunner(modelContainer: container)
    }

    /// Scrapes now and starts the repeating schedule. Idempotent — the main window's
    /// `.task` fires again every time the window is reopened.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task { await refreshNow() }

        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(ScrapeSchedule.nextInterval()))
                } catch {
                    return  // cancelled
                }
                await self?.refreshNow()
            }
        }
    }

    func stop() {
        scheduleTask?.cancel()
        scheduleTask = nil
        hasStarted = false
    }

    /// One pass over every active company. Overlapping calls (the timer firing while a
    /// manual refresh is in flight) are dropped rather than queued.
    func refreshNow() async {
        guard !isScraping else { return }
        isScraping = true
        defer { isScraping = false }

        let run = await runner.scrapeAll()
        lastRun = run

        if !run.newPostings.isEmpty {
            onNewPostings?(run.newPostings)
        }
    }
}

/// §7: every 15 minutes, jittered so every source isn't hit on the same tick.
enum ScrapeSchedule {
    static let interval: TimeInterval = 15 * 60
    static let jitter: TimeInterval = 2 * 60

    static func nextInterval() -> TimeInterval {
        interval + .random(in: -jitter...jitter)
    }
}
