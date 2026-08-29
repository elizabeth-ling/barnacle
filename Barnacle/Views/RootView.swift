import SwiftUI

/// The two tabs described in §8. The real screens land in specs `02` (Feed) and `05` (Applied);
/// this is the shell that hosts them.
struct RootView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "tray.full") }

            AppliedView()
                .tabItem { Label("Applied", systemImage: "checkmark.circle") }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    RootView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
