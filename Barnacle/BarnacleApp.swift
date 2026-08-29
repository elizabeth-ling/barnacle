import SwiftUI
import SwiftData

/// Window identifiers, so the menu-bar extra can reopen the main window by id.
enum BarnacleWindow {
    static let main = "barnacle.main"
}

@main
struct BarnacleApp: App {
    /// Owned by the app so the scrape schedule outlives any window (spec `01`).
    @State private var scrapeCoordinator = ScrapeCoordinator(container: BarnacleStore.shared)

    var body: some Scene {
        // A single main window rather than a WindowGroup: this is a one-window app,
        // and closing it should leave the menu-bar extra running (§8).
        Window("Barnacle", id: BarnacleWindow.main) {
            RootView()
                .environment(scrapeCoordinator)
                .task { scrapeCoordinator.start() }
        }
        .defaultSize(width: 820, height: 560)
        .modelContainer(BarnacleStore.shared)

        // Keeps the app alive in the background so the scrape loop (spec `01`) and the
        // global hotkey (spec `05`) keep working with no window open.
        MenuBarExtra("Barnacle", systemImage: "shippingbox") {
            MenuBarContent()
                .environment(scrapeCoordinator)
        }
        .modelContainer(BarnacleStore.shared)

        Settings {
            SettingsView()
        }
    }
}
