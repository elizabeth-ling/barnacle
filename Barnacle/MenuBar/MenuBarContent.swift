import SwiftUI
import AppKit

/// Menu-bar extra contents (§8). The unread-new count belongs on the label and lands with
/// spec `04`.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator

    var body: some View {
        Button("Open Barnacle") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: BarnacleWindow.main)
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
