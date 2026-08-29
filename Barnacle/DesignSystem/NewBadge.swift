import SwiftUI

/// The "NEW" pill: 10pt uppercase accent text on `accent/tintBg`. Sits beside a row title.
struct NewBadge: View {
    var text = "New"

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.microLabel)
            .tracking(Theme.Typography.microLabelTracking)
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Theme.Palette.accentTint, in: Capsule())
    }
}

#Preview("New badge") {
    HStack(spacing: 6) {
        Text("Software Engineer Intern, Payments")
            .font(Theme.Typography.rowTitle)
            .foregroundStyle(Theme.Palette.textPrimary)
        NewBadge()
    }
    .padding(24)
    .screenBackground()
}
