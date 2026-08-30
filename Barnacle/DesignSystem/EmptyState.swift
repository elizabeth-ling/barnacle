import SwiftUI

/// Quiet empty state for a list-shaped screen. `ContentUnavailableView` would drop a system
/// large-title into the middle of a tiny-font design, so this keeps the type scale.
///
/// The optional `actions` slot carries a call to action — the Feed's "Refresh now" (spec `02`)
/// — so the button stays centered with the message instead of being pushed to the screen edge.
struct EmptyState<Actions: View>: View {
    let title: String
    var message: String?
    var systemImage: String?
    @ViewBuilder var actions: () -> Actions

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

            actions()
                .padding(.top, 4)
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(title: String, message: String? = nil, systemImage: String? = nil) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
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

#Preview("Empty state with action") {
    EmptyState(
        title: "No internships found yet",
        message: "We check every 15 minutes.",
        systemImage: "clock"
    ) {
        Button("Refresh now") {}
            .buttonStyle(.barnacleSecondary)
    }
    .frame(width: 420, height: 220)
    .screenBackground()
}
