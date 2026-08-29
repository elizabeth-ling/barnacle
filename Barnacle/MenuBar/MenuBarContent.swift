import SwiftUI
import AppKit

/// Menu-bar extra contents (§8). The unread-new count belongs on the label and lands with
/// spec `04`; "Refresh now" gets wired to the scrape loop in spec `01`.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Barnacle") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: BarnacleWindow.main)
        }

        Button("Refresh Now") {
            // Wired to the scrape loop in spec 01.
        }
        .disabled(true)

        Divider()

        Button("Quit Barnacle") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
