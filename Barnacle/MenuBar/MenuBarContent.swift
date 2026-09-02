import SwiftUI
import AppKit

/// Menu-bar extra contents (§8). The unread-new count belongs on the label and lands with
/// spec `04`.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(QuickAddOverlay.self) private var overlay

    var body: some View {
        Button("Open Barnacle") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: BarnacleWindow.main)
        }

        // The same panel ⌘J opens, for when another app has claimed that shortcut. No
        // `keyboardShortcut` here: the global hotkey already fires while Barnacle is frontmost,
        // and a second binding would only race it.
        Button("Log Application (\u{2318}J)") {
            overlay.show()
        }

        Button(scrapeCoordinator.isScraping ? "Refreshing\u{2026}" : "Refresh Now") {
            Task { await scrapeCoordinator.refreshNow() }
        }
        .disabled(scrapeCoordinator.isScraping)

        Divider()

        Button("Quit Barnacle") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
