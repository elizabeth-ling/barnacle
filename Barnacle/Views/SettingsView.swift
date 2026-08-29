import SwiftUI

/// Placeholder settings surface (§8). Notification prefs land in spec `04`; the optional
/// ntfy topic and Claude API key come later still.
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings arrive with notifications (spec 04).")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 160)
    }
}

#Preview {
    SettingsView()
}
