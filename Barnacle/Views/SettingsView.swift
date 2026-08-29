import SwiftUI

/// Placeholder settings surface (§8). Notification prefs land in spec `04`; the optional
/// ntfy topic and Claude API key come later still.
struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text("Settings")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Notification preferences arrive with spec 04.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(width: 420, height: 160, alignment: .topLeading)
        .screenBackground()
        .preferredColorScheme(.light)
    }
}

#Preview {
    SettingsView()
}
