import SwiftUI
import AppKit
import UserNotifications

/// Notification preferences (spec `04`): the native on/off switch, and the optional ntfy push
/// that reaches the user's iPhone when they're away from the Mac.
struct SettingsView: View {
    @Environment(NotificationService.self) private var notifications

    @State private var testState = PhoneTestState.idle

    var body: some View {
        @Bindable var preferences = notifications.preferences

        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
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
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(width: 460, alignment: .topLeading)
        .screenBackground()
        .preferredColorScheme(.light)
        .task { await notifications.refreshAuthorizationStatus() }
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

    private enum PhoneTestState: Equatable {
        case idle
        case sending
        case succeeded
        case failed(String)
    }
}

#Preview {
    SettingsView()
        .environment(NotificationService())
}
