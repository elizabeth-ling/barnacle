import SwiftUI

/// Quiet empty state for a list-shaped screen. `ContentUnavailableView` would drop a system
/// large-title into the middle of a tiny-font design, so this keeps the type scale.
struct EmptyState: View {
    let title: String
    var message: String?
    var systemImage: String?

    var body: some View {
        VStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.bottom, 2)
            }

            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            if let message {
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty state") {
    EmptyState(
        title: "No postings yet",
        message: "Add a company to start tracking internships.",
        systemImage: "tray"
    )
    .frame(width: 420, height: 220)
    .screenBackground()
}
