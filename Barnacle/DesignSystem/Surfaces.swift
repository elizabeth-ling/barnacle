import SwiftUI

/// A true 1px separator. `Divider()` reads too heavy for the dense lists the spec asks for.
struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(height: 1 / displayScale)
    }
}

extension View {
    /// The warm-white app background (`bg/primary`).
    func screenBackground() -> some View {
        background(Theme.Palette.background)
    }

    /// Card / modal / overlay surface: `bg/surface`, ~12pt radius, hairline edge, soft shadow.
    /// Used by the add-company modal (`03`) and the `⌘J` overlay (`05`).
    func surfaceCard(
        radius: CGFloat = Theme.Metrics.surfaceRadius,
        padding: CGFloat = Theme.Metrics.screenPadding
    ) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.surface)
                    .shadow(
                        color: Theme.Metrics.shadowColor,
                        radius: Theme.Metrics.shadowRadius,
                        y: Theme.Metrics.shadowOffsetY
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
    }
}

#Preview("Surface card") {
    VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
        Text("Add company")
            .font(Theme.Typography.sectionTitle)
            .foregroundStyle(Theme.Palette.textPrimary)
        Text("Paste a careers page URL. Barnacle figures out the ATS.")
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textSecondary)
        Hairline()
        HStack(spacing: 8) {
            Button("Cancel") {}.buttonStyle(.barnacleSecondary)
            Button("Add") {}.buttonStyle(.barnaclePrimary)
        }
    }
    .frame(width: 260, alignment: .leading)
    .surfaceCard()
    .padding(24)
    .screenBackground()
}
