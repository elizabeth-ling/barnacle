import SwiftUI
import SwiftData

/// Window identifiers, so the menu-bar extra can reopen the main window by id.
enum BarnacleWindow {
    static let main = "barnacle.main"
}

@main
struct BarnacleApp: App {
    /// Owned by the app so the scrape schedule outlives any window (spec `01`).
    @State private var scrapeCoordinator: ScrapeCoordinator

    /// Consumes the coordinator's new-posting batches (spec `04`).
    @State private var notifications: NotificationService

    /// Owns the global ⌘J hotkey and the floating panel behind it (spec `05`). On the app for
    /// the same reason as the coordinator: it has to outlive every window.
    @State private var overlay: QuickAddOverlay

    init() {
        let notifications = NotificationService()
        // Before the app finishes launching: a notification clicked while Barnacle is closed
        // launches it and delivers the response during startup.
        notifications.registerNotificationDelegate()

        let scrapeCoordinator = ScrapeCoordinator(container: BarnacleStore.shared)
        scrapeCoordinator.onNewPostings = { postings in
            notifications.notify(about: postings)
        }

        // Registered here rather than from a view: ⌘J has to work with no window open, and a
        // launch that restores to a closed window would never run a view's `.task`.
        let overlay = QuickAddOverlay(container: BarnacleStore.shared)
        overlay.start()

        _notifications = State(initialValue: notifications)
        _scrapeCoordinator = State(initialValue: scrapeCoordinator)
        _overlay = State(initialValue: overlay)
    }

    var body: some Scene {
        // A single main window rather than a WindowGroup: this is a one-window app,
        // and closing it should leave the menu-bar extra running (§8).
        Window("Barnacle", id: BarnacleWindow.main) {
            RootView()
                .environment(scrapeCoordinator)
                .environment(notifications)
                .registersMainWindowOpener(with: notifications)
                // Two tasks, not one: `requestAuthorization` suspends until the user answers
                // the system prompt, and the first scrape must not wait behind that.
                .task { scrapeCoordinator.start() }
                .task { await notifications.requestAuthorization() }
        }
        .defaultSize(width: 820, height: 560)
        .modelContainer(BarnacleStore.shared)

        // Keeps the app alive in the background so the scrape loop (spec `01`) and the
        // global hotkey (spec `05`) keep working with no window open.
        MenuBarExtra("Barnacle", systemImage: "shippingbox") {
            MenuBarContent()
                .environment(scrapeCoordinator)
                .environment(overlay)
        }
        .modelContainer(BarnacleStore.shared)

        Settings {
            SettingsView()
                .environment(notifications)
        }
    }
}
