import SwiftUI

/// Colour for `ApplicationStatus`. The mapping lives here rather than on the model so the enum
/// stays UI-free (it's `Sendable` and used off the main actor); `Theme.Palette.Status` holds
/// the values.
extension ApplicationStatus {
    /// Text and glyph colour.
    var color: Color {
        switch self {
        case .applied: Theme.Palette.Status.applied
        case .interviewing: Theme.Palette.Status.interviewing
        case .offer: Theme.Palette.Status.offer
        case .rejected: Theme.Palette.Status.rejected
        case .ghosted: Theme.Palette.Status.ghosted
        }
    }

    /// The light fill that colour sits on.
    var tint: Color {
        switch self {
        case .applied: Theme.Palette.Status.appliedTint
        case .interviewing: Theme.Palette.Status.interviewingTint
        case .offer: Theme.Palette.Status.offerTint
        case .rejected: Theme.Palette.Status.rejectedTint
        case .ghosted: Theme.Palette.Status.ghostedTint
        }
    }
}

/// A read-only status pill: the status name in its own colour on its own tint.
struct StatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        Text(status.displayName)
            .font(Theme.Typography.metadata)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.tint, in: Capsule())
    }
}

/// A 6pt dot in the status colour — for places too tight for the pill, like the counts strip.
struct StatusDot: View {
    let status: ApplicationStatus
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

/// The inline status dropdown, shared by the Applied row and the edit form. Written by hand
/// rather than as a `Picker` so it wears the design system's chrome — here, the status's own
/// colour on its own tint — instead of a system pop-up button.
struct StatusSelector: View {
    @Binding var selection: ApplicationStatus

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(ApplicationStatus.allCases, id: \.self) { status in
                Button(status.displayName) { selection = status }
            }
        } label: {
            HStack(spacing: 4) {
                StatusDot(status: selection, size: 5)
                Text(selection.displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(Theme.Typography.metadata)
            .foregroundStyle(selection.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                selection.tint,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                    // Hover firms up the border rather than changing the fill, so the status
                    // colour stays the thing that reads.
                    .strokeBorder(selection.color.opacity(isHovered ? 0.55 : 0.25), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        // `.borderlessButton` throws the label away and lets AppKit draw its own menu — the
        // status colour, the dot, and the pill never survived it. `.button` + `.plain` keeps
        // the label exactly as written while staying a real menu.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        .help("Change status")
    }
}

#Preview("Statuses") {
    struct Host: View {
        @State private var selection = ApplicationStatus.interviewing

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(ApplicationStatus.allCases, id: \.self) { StatusBadge(status: $0) }
                }
                StatusSelector(selection: $selection)
            }
            .padding(24)
            .screenBackground()
        }
    }

    return Host()
}
