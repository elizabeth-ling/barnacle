import SwiftUI

/// The two tabs described in §8. The real screens land in specs `02` (Feed) and `05` (Applied);
/// this is the shell that hosts them, wearing spec `06`'s palette.
struct RootView: View {
    /// Onboarding (spec `09`) runs until it has been seen once. A sheet over this window rather
    /// than a separate scene, so the app keeps its one-window shape (§8).
    @AppStorage(OnboardingView.completedKey) private var hasCompletedOnboarding = false

    /// Dismissing the sheet any other way (Skip does it explicitly) counts as having seen it —
    /// the defaults it would have written are already in place.
    private var isShowingOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

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
        .sheet(isPresented: isShowingOnboarding) {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
        .environment(ScrapeCoordinator(container: BarnacleStore.makeContainer(inMemory: true)))
        .environment(NotificationService())
        .environment(ScrapePreferences())
}
