import SwiftUI
import SwiftData
import AppKit
import UserNotifications

/// The app's settings: what to look for (spec `07`) over the notification switches (spec `04`)
/// — the native on/off toggle and the optional ntfy push that reaches the user's iPhone.
struct SettingsView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(ScrapePreferences.self) private var scrapePreferences
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(\.modelContext) private var modelContext

    /// Every posting, counted in memory — the same one-user scale that lets the Feed sort in
    /// memory, and the purge dialog has to state a count before anything is deleted.
    @Query private var postings: [JobPosting]

    @State private var testState = PhoneTestState.idle

    /// Cleared by "Show onboarding again" (spec `09`) — `RootView` presents the flow whenever
    /// this is false, so clearing it is the whole of re-presenting.
    @AppStorage(OnboardingView.completedKey) private var hasCompletedOnboarding = false

    /// Settings is its own window, so the flow would otherwise wait for the main window to be
    /// reopened by hand.
    @Environment(\.openWindow) private var openWindow

    /// A settings change that would delete postings, held until the user confirms it.
    @State private var pendingPurge: PendingPurge?

    private var isConfirmingPurge: Binding<Bool> {
        Binding(
            get: { pendingPurge != nil },
            set: { if !$0 { pendingPurge = nil } }
        )
    }

    var body: some View {
        @Bindable var preferences = notifications.preferences

        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            ScrapeSettingsSection(
                preferences: scrapePreferences,
                onSelectRoleLevel: requestRoleLevel,
                onSelectCountries: requestCountries
            )

            Hairline()
                .padding(.vertical, 2)

            Text("Notifications")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Toggle(isOn: $preferences.isEnabled) {
                Text("Tell me when new internships appear")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)

            Text("One notification per check, however many postings it found.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)

            if notifications.authorizationStatus == .denied {
                systemSettingsWarning
            }

            Hairline()
                .padding(.vertical, 2)

            phoneSection(preferences: preferences)

            Hairline()
                .padding(.vertical, 2)

            onboardingSection
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(width: 460, alignment: .topLeading)
        .screenBackground()
        .preferredColorScheme(.light)
        .task { await notifications.refreshAuthorizationStatus() }
        // The one destructive action in the app, so it always states the count first.
        .confirmationDialog(
            pendingPurge?.title ?? "Remove postings?",
            isPresented: isConfirmingPurge,
            presenting: pendingPurge
        ) { purge in
            Button(purge.count == 1 ? "Remove 1 posting" : "Remove \(purge.count) postings", role: .destructive) {
                apply(purge.change)
            }
            Button("Cancel", role: .cancel) {}
        } message: { purge in
            Text(purge.message)
        }
    }

    /// The only way to see the first-run flow twice without deleting the container (spec `09`).
    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text("Onboarding")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            HStack(spacing: 8) {
                Button("Show onboarding again") {
                    hasCompletedOnboarding = false
                    openWindow(id: BarnacleWindow.main)
                }
                .buttonStyle(.barnacleSecondary)

                Spacer(minLength: 8)
            }

            Text("Walks back through role, countries, and companies in the main window. Nothing is reset \u{2014} the steps start from what\u{2019}s set here.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The toggle above is a lie while macOS is blocking Barnacle, so say so and offer the fix.
    private var systemSettingsWarning: some View {
        HStack(spacing: 8) {
            Text("macOS is blocking notifications for Barnacle.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer(minLength: 8)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.barnacleSecondary)
        }
        .padding(8)
        .background(Theme.Palette.accentTint, in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous))
    }

    @ViewBuilder
    private func phoneSection(preferences: NotificationPreferences) -> some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Toggle(isOn: $preferences.isPhonePushEnabled) {
                Text("Also send to my iPhone")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)

            Text("Install the free ntfy app on your iPhone and subscribe to this topic. Anyone who knows a public topic name can read it \u{2014} generate a random one.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if preferences.isPhonePushEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Topic or server URL")
                    HStack(spacing: 8) {
                        TextField("barnacle-\u{2026}", text: $preferences.ntfyTopic)
                            .barnacleField()
                            .onChange(of: preferences.ntfyTopic) { _, _ in testState = .idle }

                        Button("Generate") {
                            preferences.ntfyTopic = NtfyDestination.randomTopic()
                            testState = .idle
                        }
                        .buttonStyle(.barnacleSecondary)
                    }

                    Text(topicHelpText(for: preferences.ntfyTopic))
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Button(testState == .sending ? "Sending\u{2026}" : "Send test") {
                        sendTest()
                    }
                    .buttonStyle(.barnacleSecondary)
                    .disabled(testState == .sending || NtfyDestination.url(from: preferences.ntfyTopic) == nil)

                    testStatus
                }
            }
        }
        .disabled(!preferences.isEnabled)
        .opacity(preferences.isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle, .sending:
            EmptyView()
        case .succeeded:
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.success)
        case .failed(let message):
            Text(message)
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.accentHover)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shows exactly where a batch would be published, so a typo is visible before it costs the
    /// user a missed posting.
    private func topicHelpText(for topic: String) -> String {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "A bare name publishes to \(NtfyDestination.defaultServer); a full URL works for a self-hosted server."
        }
        guard let url = NtfyDestination.url(from: trimmed) else {
            return "Not a valid ntfy topic or server URL."
        }
        return "Publishing to \(url.absoluteString)"
    }

    private func sendTest() {
        testState = .sending
        Task {
            do {
                try await notifications.sendTestPhonePush()
                testState = .succeeded
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - What to look for (spec `07`)

    /// A change the user asked for, and what applying it would cost.
    private struct PendingPurge: Identifiable {
        let id = UUID()
        let change: Change
        let count: Int
        let title: String
        let message: String
    }

    private enum Change {
        case roleLevel(RoleLevel)
        case countries(Set<String>)
    }

    private func requestRoleLevel(_ level: RoleLevel) {
        guard level != scrapePreferences.roleLevel else { return }

        var proposed = scrapePreferences.filter
        proposed.roleLevel = level
        let doomed = PostingPurge.unmatched(postings, under: proposed).count
        guard doomed > 0 else {
            apply(.roleLevel(level))
            return
        }

        let noun = scrapePreferences.roleLevel.postingNoun
        let destination = level.displayName.lowercased()
        pendingPurge = PendingPurge(
            change: .roleLevel(level),
            count: doomed,
            title: "Switch to \(destination)?",
            message: doomed == 1
                ? "Switching to \(destination) will remove 1 \(noun) posting."
                : "Switching to \(destination) will remove \(doomed) \(noun) postings."
        )
    }

    private func requestCountries(_ codes: Set<String>) {
        guard codes != scrapePreferences.countries else { return }

        var proposed = scrapePreferences.filter
        proposed.countries = codes
        let doomed = PostingPurge.unmatched(postings, under: proposed).count
        guard doomed > 0 else {
            apply(.countries(codes))
            return
        }

        pendingPurge = PendingPurge(
            change: .countries(codes),
            count: doomed,
            title: "Change countries?",
            message: doomed == 1
                ? "1 stored posting is somewhere you\u{2019}d no longer be watching. It will be removed."
                : "\(doomed) stored postings are somewhere you\u{2019}d no longer be watching. They will be removed."
        )
    }

    /// Writes the setting, deletes what it stranded, and refreshes so the feed refills in the
    /// same beat instead of looking empty until the next scheduled scrape.
    private func apply(_ change: Change) {
        switch change {
        case .roleLevel(let level): scrapePreferences.roleLevel = level
        case .countries(let codes): scrapePreferences.countries = codes
        }
        pendingPurge = nil

        PostingPurge.purge(postings, under: scrapePreferences.filter, in: modelContext)
        // Saved rather than left to autosave, matching the other delete path in the app
        // (`ManageCompaniesView.remove`): the refresh that follows writes to the same store.
        try? modelContext.save()

        Task { await scrapeCoordinator.refreshNow() }
    }

    private enum PhoneTestState: Equatable {
        case idle
        case sending
        case succeeded
        case failed(String)
    }
}

#Preview {
    SettingsView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
        .environment(NotificationService())
        .environment(ScrapePreferences())
        .environment(ScrapeCoordinator(container: BarnacleStore.makeContainer(inMemory: true)))
}
