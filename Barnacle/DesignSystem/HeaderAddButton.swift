import SwiftUI

/// The primary "add" action, sized to sit in a `ScreenHeader`'s trailing control row next to
/// the quiet controls: accent fill, white glyph, the same height and radius they use.
///
/// This replaces the floating bottom-right circle on both screens — the filter, sort, refresh,
/// and add controls now live together in the top bar instead of at opposite corners.
struct HeaderAddButton: View {
    var systemImage = "plus"
    var help = ""
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                // Matches `.quietControl`'s box: 8pt across, and a vertical inset that lands on
                // the same height as its 11pt label.
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isHovered ? Theme.Palette.accentHover : Theme.Palette.accent,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        .help(help)
    }
}

#Preview("Header add") {
    VStack(spacing: 0) {
        ScreenHeader(title: "Feed") {
            HStack(spacing: 6) {
                Button("All companies") {}.buttonStyle(.quietControl())
                Button("Newest") {}.buttonStyle(.quietControl(isActive: true))
                HeaderAddButton(help: "Add a company") {}
            }
        }
        Spacer()
    }
    .frame(width: 480, height: 160)
    .screenBackground()
}
