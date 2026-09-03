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

    /// What to keep (spec `07`). Read fresh at the top of every run, so a settings change takes
    /// effect on the next scrape without a restart.
    @ObservationIgnored let preferences: ScrapePreferences

    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    /// - Parameter preferences: the app passes the one instance Settings also edits. Nil builds
    ///   a fresh reader of the same defaults, which is what previews want — a default argument
    ///   can't do it, since those are evaluated off the main actor.
    init(container: ModelContainer, preferences: ScrapePreferences? = nil) {
        runner = ScrapeRunner(modelContainer: container)
        self.preferences = preferences ?? ScrapePreferences()
    }

    /// Scrapes now and starts the repeating schedule. Idempotent — the main window's
    /// `.task` fires again every time the window is reopened.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await backfillRegionsIfNeeded()
            await refreshNow()
        }

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

        let run = await runner.scrapeAll(filter: preferences.filter)
        lastRun = run

        if !run.newPostings.isEmpty {
            onNewPostings?(run.newPostings)
        }
    }
}

/// Classifies the postings stored before spec `07` shipped, once (§`07`, "Backfill"). The flag
/// lives in `UserDefaults` alongside the settings themselves; `bool(forKey:)` is right here,
/// because an unset key genuinely means "not yet backfilled."
private extension ScrapeCoordinator {
    func backfillRegionsIfNeeded() async {
        guard !preferences.didBackfillRegions else { return }
        let stamped = await runner.backfillRegions()
        preferences.didBackfillRegions = true
        if stamped > 0 {
            ScrapeLog.logger.info("Backfilled country codes for \(stamped, privacy: .public) postings")
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
