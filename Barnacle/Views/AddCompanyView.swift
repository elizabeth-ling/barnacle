import SwiftUI
import SwiftData

/// The add-company modal (spec `03`): a name, one or more careers URLs, and a check that runs
/// before anything is saved. Opened by the Feed's floating `+`.
///
/// `Return` submits, `Esc` cancels. Chrome is spec `06`'s warm surface, serif title, tiny fields.
struct AddCompanyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = AddCompanyModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case url(UUID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text("Add company")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Hairline()

            nameField
            urlFields

            if let formError = model.formError {
                Text(formError)
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(model.awaitingConfirmation ? Theme.Palette.textSecondary : Theme.Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Hairline()

            footer
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(width: 420)
        .background(Theme.Palette.surface)
        // A sheet is its own window, so it doesn't inherit the main window's pinned appearance
        // — same light-only caveat as `RootView`.
        .preferredColorScheme(.light)
        .onAppear { focusedField = .name }
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Company name")
            TextField("Acme", text: $model.name)
                .barnacleField(isFocused: focusedField == .name)
                .focused($focusedField, equals: .name)
                .onSubmit(submit)
        }
    }

    private var urlFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(model.urlFields.count > 1 ? "Careers URLs" : "Careers URL")

            ForEach(model.urlFields) { field in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        TextField("boards.greenhouse.io/acme", text: model.textBinding(for: field.id))
                            .barnacleField(isFocused: focusedField == .url(field.id))
                            .focused($focusedField, equals: .url(field.id))
                            .onSubmit(submit)

                        if model.urlFields.count > 1 {
                            Button {
                                model.removeURLField(id: field.id)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.quietControl())
                            .disabled(model.isChecking)
                            .help("Remove this URL")
                        }
                    }

                    URLCheckStatus(field: field)
                }
            }

            Button("+ add another URL") {
                model.addURLField()
            }
            .buttonStyle(.quietControl())
            .disabled(model.isChecking)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isChecking {
                ProgressView()
                    .controlSize(.small)
                Text("Checking\u{2026}")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 8)

            Button("Cancel") { dismiss() }
                .buttonStyle(.barnacleSecondary)
                .keyboardShortcut(.cancelAction)

            Button(model.primaryButtonTitle, action: submit)
                .buttonStyle(.barnaclePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmit)
        }
    }

    // MARK: - Actions

    /// First press checks; a second press after a warning is the spec's "save anyway."
    private func submit() {
        guard model.canSubmit else { return }

        if model.awaitingConfirmation {
            save()
            return
        }

        Task {
            if await model.check() {
                save()
            }
        }
    }

    private func save() {
        guard let company = model.makeCompany() else {
            model.reportNothingToSave()
            return
        }
        modelContext.insert(company)

        // Not `try?`: swallowing this would dismiss the modal as though it worked and lose
        // everything the user typed, with the company nowhere to be found afterwards.
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(company)
            model.reportSaveFailure(error)
            return
        }
        dismiss()
    }
}

/// The per-URL result line: what we detected, and what the test fetch said (spec `03`).
private struct URLCheckStatus: View {
    let field: AddCompanyModel.URLField

    var body: some View {
        if field.isChecking {
            line(icon: "arrow.triangle.2.circlepath", color: Theme.Palette.textSecondary, text: "Checking\u{2026}")
        } else {
            switch field.outcome {
            case .reachable(let detection, let count):
                line(
                    icon: "checkmark.circle.fill",
                    color: Theme.Palette.success,
                    text: "\(detection.atsType.displayName) \u{00B7} \(Self.internshipCount(count))"
                )
            case .noAdapterYet(let detection):
                line(
                    icon: "clock",
                    color: Theme.Palette.textSecondary,
                    text: "\(detection.atsType.displayName) detected \u{2014} no adapter for it yet, so it won\u{2019}t return postings."
                )
            case .unreachable(let detection, let message):
                line(
                    icon: "exclamationmark.triangle",
                    color: Theme.Palette.accent,
                    text: "\(detection.atsType.displayName) detected, but the test fetch failed. Saving stores it as a generic page.",
                    help: message
                )
            case .invalid(let message):
                line(icon: "exclamationmark.triangle", color: Theme.Palette.accent, text: message)
            case nil:
                EmptyView()
            }
        }
    }

    private func line(icon: String, color: Color, text: String, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.Typography.metadata)
        .foregroundStyle(color)
        .help(help ?? "")
    }

    private static func internshipCount(_ count: Int) -> String {
        switch count {
        case 0: "No internships listed right now"
        case 1: "Found 1 internship"
        default: "Found \(count) internships"
        }
    }
}

#Preview("Add company") {
    AddCompanyView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
