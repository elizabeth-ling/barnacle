import SwiftUI

/// Primary (accent fill, white text) and secondary (surface, hairline border) buttons.
struct BarnacleButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> some View {
        // Hover needs @State, which a ButtonStyle can't hold — so the body is its own view.
        StyleBody(configuration: configuration, variant: variant)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant

        @State private var isHovered = false

        private var isPrimary: Bool { variant == .primary }

        private var fill: Color {
            let active = isHovered || configuration.isPressed
            if isPrimary {
                return active ? Theme.Palette.accentHover : Theme.Palette.accent
            }
            return active ? Theme.Palette.surfaceAlt : Theme.Palette.surface
        }

        var body: some View {
            configuration.label
                .font(Theme.Typography.body)
                .foregroundStyle(isPrimary ? Color.white : Theme.Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                        .strokeBorder(isPrimary ? Color.clear : Theme.Palette.hairline, lineWidth: 1)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        }
    }
}

/// The quiet controls of the Feed's filter/sort row: hairline border, secondary text, accent
/// only once active.
struct QuietControlButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isActive: isActive)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let isActive: Bool

        @State private var isHovered = false

        private var fill: Color {
            if isActive { return Theme.Palette.accentTint }
            return isHovered || configuration.isPressed ? Theme.Palette.surfaceAlt : Theme.Palette.surface
        }

        var body: some View {
            configuration.label
                .font(Theme.Typography.metadata)
                .foregroundStyle(isActive ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                        .strokeBorder(isActive ? Theme.Palette.accent : Theme.Palette.hairline, lineWidth: 1)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        }
    }
}

extension ButtonStyle where Self == BarnacleButtonStyle {
    static var barnaclePrimary: BarnacleButtonStyle { BarnacleButtonStyle(variant: .primary) }
    static var barnacleSecondary: BarnacleButtonStyle { BarnacleButtonStyle(variant: .secondary) }
}

extension ButtonStyle where Self == QuietControlButtonStyle {
    static func quietControl(isActive: Bool = false) -> QuietControlButtonStyle {
        QuietControlButtonStyle(isActive: isActive)
    }
}

#Preview("Buttons") {
    VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
            Button("Add company") {}.buttonStyle(.barnaclePrimary)
            Button("Cancel") {}.buttonStyle(.barnacleSecondary)
        }
        HStack(spacing: 6) {
            Button("All companies") {}.buttonStyle(.quietControl())
            Button("Newest") {}.buttonStyle(.quietControl(isActive: true))
            Button("Oldest") {}.buttonStyle(.quietControl())
        }
    }
    .padding(24)
    .screenBackground()
}
