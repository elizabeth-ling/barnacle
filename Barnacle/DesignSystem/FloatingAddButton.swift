import SwiftUI

/// The Feed's primary action: a circular accent button with a white glyph and a soft shadow.
struct FloatingAddButton: View {
    var systemImage = "plus"
    var help = ""
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: Theme.Metrics.floatingButtonSize, height: Theme.Metrics.floatingButtonSize)
                .background(isHovered ? Theme.Palette.accentHover : Theme.Palette.accent, in: Circle())
                .shadow(
                    color: Theme.Metrics.shadowColor,
                    radius: Theme.Metrics.shadowRadius,
                    y: Theme.Metrics.shadowOffsetY
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        .help(help)
    }
}

extension View {
    /// Places the floating `+` bottom-right with the spec's ~20pt margins.
    func floatingAddButton(help: String = "", action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            FloatingAddButton(help: help, action: action)
                .padding(Theme.Metrics.floatingButtonMargin)
        }
    }
}

#Preview("Floating add") {
    Color.clear
        .frame(width: 320, height: 200)
        .screenBackground()
        .floatingAddButton(help: "Add a company") {}
}
