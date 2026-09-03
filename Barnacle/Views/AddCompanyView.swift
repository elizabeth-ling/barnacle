import SwiftUI
import SwiftData

/// The add-company modal (spec `03`): a name, one or more careers URLs, and a check that runs
/// before anything is saved. Opened by the Feed's `+`.
///
/// Typing just a name and pressing `Return` probes for the company's job board (spec `08`) —
/// the URL field stays as the fallback for a name nothing answers to.
///
/// `Return` submits, `Esc` cancels. Chrome is spec `06`'s warm surface, serif title, tiny fields.
struct AddCompanyView: View {
    /// When set, the modal edits this company's URLs in place instead of creating one
    /// (spec `08`, "Fixing a wrong URL"). Same fields, same checker, detection re-run on save.
    var company: Company?

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
            Text(company == nil ? "Add company" : "Edit company")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Hairline()

            nameField
            boardResults
            urlFields

            if let formError = model.formError {
                Text(formError)
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(model.formErrorIsAdvisory ? Theme.Palette.textSecondary : Theme.Palette.accent)
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
        .onAppear {
            if let company {
                model.load(from: company)
                focusedField = model.urlFields.first.map { .url($0.id) }
            } else {
                focusedField = .name
            }
        }
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Company name")
            TextField("Acme", text: $model.name)
                .barnacleField(isFocused: focusedField == .name)
                .focused($focusedField, equals: .name)
                .onSubmit(submit)

            // The whole point of spec `08` is that the URL is optional, which is only obvious
            // if we say so — and only while it's still true.
            if model.search == .idle && !model.hasEnteredURL {
                Text("Press Return to look for its job board.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    /// What probing the name turned up (spec `08`): a spinner, the boards that answered, or
    /// nothing — in which case the message under the fields points at the URL field instead.
    @ViewBuilder private var boardResults: some View {
        switch model.search {
        case .idle, .notFound:
            EmptyView()

        case .searching:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking for a job board\u{2026}")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

        case .found(let boards):
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel(boards.count == 1 ? "Found a job board" : "Found \(boards.count) job boards \u{2014} pick one")

                VStack(spacing: 0) {
                    ForEach(boards) { board in
                        if board.id != boards.first?.id {
                            Hairline()
                        }
                        BoardResultRow(
                            board: board,
                            companyName: model.trimmedName,
                            isSelected: model.selectedBoardID == board.id
                        ) {
                            model.select(board)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
            }
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

    /// A name on its own probes for a board (spec `08`); once there's a URL this is spec `03`'s
    /// check, and a second press after a warning is its "save anyway."
    private func submit() {
        guard model.canSubmit else { return }

        switch model.submitAction {
        case .findBoards:
            Task {
                await model.findBoards()
                // Nothing answered: the URL field is the fallback, so put the cursor in it
                // rather than leaving the user to find it.
                if model.search == .notFound, let first = model.urlFields.first {
                    focusedField = .url(first.id)
                }
            }

        case .chooseBoard:
            model.reportBoardChoiceNeeded()

        case .saveAnyway:
            save()

        case .check:
            Task {
                if await model.check() {
                    save()
                }
            }
        }
    }

    private func save() {
        if let company {
            saveEdits(to: company)
        } else {
            saveNewCompany()
        }
    }

    private func saveNewCompany() {
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

    /// The edit path (spec `08`). No rollback on failure, deliberately: `rollback()` would also
    /// discard unrelated pending changes on the shared context, and the modal stays open with
    /// the message so the user can try again.
    private func saveEdits(to company: Company) {
        guard model.apply(to: company) else {
            model.reportNothingToSave()
            return
        }

        do {
            try modelContext.save()
        } catch {
            model.reportSaveFailure(error)
            return
        }
        dismiss()
    }
}

/// One probed board (spec `08`): the company, which ATS answered, and how many roles match the
/// user's settings — which is the disambiguator when two boards answer to the same name.
private struct BoardResultRow: View {
    let board: CompanyBoard
    let companyName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        CompactRow(title: companyName, metadata: metadata, action: action) { _ in
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.hairline)
        }
        // No selected-row fill: `CompactRow` paints its own opaque background for hover, so a
        // tint behind it wouldn't show. The accent check is the selection.
        .help(board.boardURL)
    }

    private var metadata: String {
        let roles = switch board.matchingRoles {
        case 0: "no matching roles"
        case 1: "1 matching role"
        default: "\(board.matchingRoles) matching roles"
        }
        return "\(board.atsType.displayName) \u{00B7} \(roles)"
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

    /// Deliberately says "matching" rather than "internships": the count now reflects the
    /// user's role level and countries (spec `07`), and a new-grad seeker isn't being told
    /// about internships.
    private static func internshipCount(_ count: Int) -> String {
        switch count {
        case 0: "No matching roles listed right now"
        case 1: "Found 1 matching role"
        default: "Found \(count) matching roles"
        }
    }
}

#Preview("Add company") {
    AddCompanyView()
        .modelContainer(BarnacleStore.makeContainer(inMemory: true))
}
