import SwiftUI
import SwiftData
import AppKit

/// One logged application in the Applied tab (spec `05`): the compact row, its inline status
/// dropdown, and the detail the row reveals when clicked — link, notes, edit, delete.
struct ApplicationRow: View {
    @Bindable var application: Application

    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            CompactRow(
                title: application.jobTitle,
                metadata: metadata,
                action: { isExpanded.toggle() }
            ) {
                HStack(spacing: 6) {
                    StatusMenu(selection: $application.status)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }

            if isExpanded {
                detail
            }
        }
        .animation(Theme.Metrics.hoverAnimation, value: isExpanded)
    }

    private var metadata: String {
        "\(application.companyName) \u{00B7} \(PostingDateFormat.relative(application.dateApplied))"
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let link = application.url, !link.isEmpty {
                Button(action: open) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9, weight: .semibold))
                        Text(link)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
                .help("Open in your browser")
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Notes")
                TextField("Anything worth remembering", text: notesBinding, axis: .vertical)
                    .lineLimit(1...4)
                    .barnacleField()
            }

            HStack(spacing: 6) {
                Text("Applied \(PostingDateFormat.absolute(application.dateApplied))")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)

                Spacer(minLength: 8)

                Button("Edit", action: onEdit)
                    .buttonStyle(.quietControl())

                Button("Delete", action: onDelete)
                    .buttonStyle(.quietControl())
            }
        }
        .padding(.horizontal, Theme.Metrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surfaceAlt)
    }

    /// Empty notes are stored as nil, so an emptied field doesn't leave `""` behind (§5 has
    /// `notes` optional), but the raw text is written through as typed — trimming mid-keystroke
    /// would make a space impossible to type.
    private var notesBinding: Binding<String> {
        Binding(
            get: { application.notes ?? "" },
            set: { application.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private func open() {
        guard let link = application.url, let url = URL(string: link), NSWorkspace.shared.open(url) else {
            AppliedLog.logger.error("Could not open application link: \(application.url ?? "-", privacy: .public)")
            return
        }
    }

}

/// The row's inline status dropdown. Written by hand rather than as a `Picker` so it wears the
/// design system's quiet-control chrome instead of a system pop-up button.
private struct StatusMenu: View {
    @Binding var selection: ApplicationStatus

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(ApplicationStatus.allCases, id: \.self) { status in
                Button(status.displayName) { selection = status }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selection.displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(Theme.Typography.metadata)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isHovered ? Theme.Palette.surfaceAlt : Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(Theme.Metrics.hoverAnimation, value: isHovered)
        .help("Change status")
    }
}

#Preview("Application row") {
    let container = BarnacleStore.makeContainer(inMemory: true)
    let application = Application(
        companyName: "Stripe",
        jobTitle: "Software Engineer Intern, Payments",
        url: "https://boards.greenhouse.io/stripe/jobs/123",
        notes: "Referred by a friend."
    )
    container.mainContext.insert(application)

    return VStack(spacing: 0) {
        ApplicationRow(application: application, onEdit: {}, onDelete: {})
        Hairline()
    }
    .frame(width: 480)
    .modelContainer(container)
}
