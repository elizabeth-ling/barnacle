import SwiftUI

/// The two tabs described in §8. The real screens land in specs `02` (Feed) and `05` (Applied);
/// this is the shell that hosts them, wearing spec `06`'s palette.
struct RootView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "tray.full") }

            AppliedView()
                .tabItem { Label("Applied", systemImage: "checkmark.circle") }
        }
        .frame(minWidth: 640, minHeight: 420)
        .tint(Theme.Palette.accent)
        .screenBackground()
        // The palette is light warm-white only (spec `06` defers dark mode), so pin the
        // appearance rather than paint these tokens onto dark system chrome.
        .preferredColorScheme(.light)
    }
}

#Preview {
    RootView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
