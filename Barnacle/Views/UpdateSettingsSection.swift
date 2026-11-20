import SwiftUI

/// Settings' "Updates" section (spec `12`): the auto-install switch and a manual check.
struct UpdateSettingsSection: View {
    let updates: UpdateController

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "Barnacle \(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text("Updates")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            AutoUpdateToggle(updates: updates)

            HStack(spacing: 8) {
                Button("Check for Updates") { updates.checkForUpdates() }
                    .buttonStyle(.barnacleSecondary)
                    .disabled(!updates.canCheckForUpdates)

                Text(updates.isActive ? versionText : "\(versionText) \u{00B7} updates are off in Debug builds")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)

                Spacer(minLength: 8)
            }
        }
    }
}

/// The auto-install switch and the sentence that explains it.
///
/// Its own view because onboarding's last step asks the same question, and the same reasoning as
/// `UnknownLocationToggle` applies: one copy of the explanation, not two to keep in step.
struct AutoUpdateToggle: View {
    @Bindable var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Toggle(isOn: $updates.installsAutomatically) {
                Text("Install updates automatically")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)

            Text(updates.installsAutomatically
                 ? "New versions download in the background and install the next time Barnacle quits or your Mac restarts."
                 : "Barnacle still checks once a day, but asks before downloading or installing anything.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
