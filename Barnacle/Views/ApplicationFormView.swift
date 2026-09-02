import SwiftUI
import SwiftData

/// The one form that creates and edits an `Application` (spec `05`).
///
/// Rendered bare — no outer padding, background, or width — so both hosts can dress it: the
/// Applied tab shows it as a sheet, the `⌘J` overlay drops it into a floating card.
///
/// Keyboard-first, because the overlay is meant to be opened, typed through, and dismissed
/// without touching the mouse: the company field takes focus on appear, `Return` saves from
/// any field, `Esc` cancels.
struct ApplicationFormView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var model: ApplicationFormModel
    var onCancel: () -> Void
    var onSaved: () -> Void

    /// Names offered under the company field: everything tracked, plus everything already
    /// applied to. Both queries are tiny at one user's scale.
    @Query(sort: \Company.name) private var companies: [Company]
    @Query private var applications: [Application]

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case company
        case role
        case url
        case notes
    }

    private var suggestions: [String] {
        guard focusedField == .company else { return [] }
        return model.suggestions(from: companies.map(\.name) + applications.map(\.companyName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            Text(model.title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Hairline()

            companyField
            roleField
            urlField

            if model.isEditing {
                editOnlyFields
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Hairline()

            footer
        }
        .onAppear { focusedField = .company }
    }

    // MARK: - Fields

    private var companyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Company")
            TextField("Acme", text: $model.companyName)
                .barnacleField(isFocused: focusedField == .company)
                .focused($focusedField, equals: .company)
                .onSubmit(submit)

            // Inline rather than a popover: a popover is its own window, and taking key status
            // away from the overlay panel is exactly what dismisses it.
            if !suggestions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) {
                            model.acceptSuggestion(name)
                            focusedField = .role
                        }
                        .buttonStyle(.quietControl())
                    }
                }
            }
        }
    }

    private var roleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Role")
            TextField("Software Engineer Intern", text: $model.jobTitle)
                .barnacleField(isFocused: focusedField == .role)
                .focused($focusedField, equals: .role)
                .onSubmit(submit)
        }
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Link (optional)")
            TextField("boards.greenhouse.io/acme/jobs/123", text: $model.url)
                .barnacleField(isFocused: focusedField == .url)
                .focused($focusedField, equals: .url)
                .onSubmit(submit)
        }
    }

    /// Date, status, and notes only appear when editing — the create form stays short enough
    /// to fill in without thinking (spec `05`: `dateApplied` "editable in the Applied tab later").
    private var editOnlyFields: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.fieldSpacing) {
            HStack(alignment: .top, spacing: Theme.Metrics.fieldSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Applied")
                    DatePicker("", selection: $model.dateApplied, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(Theme.Typography.body)
                }

                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Status")
                    Picker("", selection: $model.status) {
                        ForEach(ApplicationStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .labelsHidden()
                    .font(Theme.Typography.body)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Notes")
                TextField("Anything worth remembering", text: $model.notes, axis: .vertical)
                    .lineLimit(2...5)
                    .barnacleField(isFocused: focusedField == .notes)
                    .focused($focusedField, equals: .notes)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)

            Button("Cancel", action: onCancel)
                .buttonStyle(.barnacleSecondary)
                .keyboardShortcut(.cancelAction)

            // Deliberately never disabled: the primary button style doesn't dim, so a disabled
            // one would just look like a button that does nothing. Submitting with a field
            // empty says so instead.
            Button(model.submitTitle, action: submit)
                .buttonStyle(.barnaclePrimary)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func submit() {
        guard model.save(in: modelContext) else { return }
        onSaved()
    }
}

/// The Applied tab's sheet dressing for the shared form.
struct ApplicationFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: ApplicationFormModel

    var body: some View {
        ApplicationFormView(model: model, onCancel: { dismiss() }, onSaved: { dismiss() })
            .padding(Theme.Metrics.screenPadding)
            .frame(width: 420)
            .background(Theme.Palette.surface)
            // A sheet is its own window, so it doesn't inherit the main window's pinned
            // appearance — same light-only caveat as `RootView`.
            .preferredColorScheme(.light)
    }
}

#Preview("Log application") {
    ApplicationFormSheet(model: ApplicationFormModel())
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
