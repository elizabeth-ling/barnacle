import SwiftUI

/// The dense list row shared by the Feed (`02`) and Applied (`05`) lists: title on top,
/// metadata under it, optional trailing detail, full-row hover in `bg/surfaceAlt`.
/// Separate rows with `Hairline()` rather than a heavy divider.
struct CompactRow<Trailing: View>: View {
    let title: String
    var metadata: String?
    var isNew = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)

                    if isNew {
                        NewBadge()
                    }
                }

                if let metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing()
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Metrics.rowHorizontalPadding)
        .padding(.vertical, Theme.Metrics.rowVerticalPadding)
        .frame(minHeight: Theme.Metrics.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Theme.Palette.surfaceAlt : Theme.Palette.surface)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        .onTapGesture { action?() }
    }
}

extension CompactRow where Trailing == EmptyView {
    init(title: String, metadata: String? = nil, isNew: Bool = false, action: (() -> Void)? = nil) {
        self.init(title: title, metadata: metadata, isNew: isNew, action: action) { EmptyView() }
    }
}

#Preview("Compact rows") {
    VStack(spacing: 0) {
        CompactRow(
            title: "Software Engineer Intern, Payments",
            metadata: "Stripe \u{00B7} Aug 29",
            isNew: true
        ) {
            Text("Seattle, WA")
        }
        Hairline()
        CompactRow(title: "Data Science Intern", metadata: "Ramp \u{00B7} Aug 27") {
            Text("New York, NY")
        }
        Hairline()
        CompactRow(title: "Security Engineering Co-op", metadata: "Figma \u{00B7} Aug 24")
    }
    .frame(width: 420)
    .screenBackground()
}
