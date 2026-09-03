import Foundation
import Observation
import SwiftUI

/// The editable state behind the add-company modal (spec `03`): the typed name, one row per
/// careers URL, and what each URL's check said.
///
/// Kept apart from the view because Add is a two-step interaction — check, then save or save
/// anyway — and that state machine is easier to read (and to reason about) on its own.
@MainActor
@Observable
final class AddCompanyModel {
    /// One careers URL row. Most companies only ever have one.
    struct URLField: Identifiable {
        let id = UUID()
        var text = ""
        /// Nil until checked, and cleared again whenever the text changes — a stale green
        /// check next to an edited URL would be a lie.
        var outcome: URLCheckOutcome?
        var isChecking = false
    }

    /// What probing the typed name turned up (spec `08`).
    enum BoardSearch: Equatable {
        case idle
        case searching
        case found([CompanyBoard])
        /// Probed, nothing answered. The URL field is the fallback, never a dead end.
        case notFound
    }

    /// Editing the name invalidates any boards found for the old one — they'd otherwise sit
    /// there describing a company the user has stopped typing.
    var name = "" {
        didSet {
            guard name != oldValue else { return }
            search = .idle
            selectedBoardID = nil
            awaitingConfirmation = false
            formError = nil
        }
    }

    var urlFields: [URLField] = [URLField()]

    /// The single message under the fields: what's missing, the spec's "save anyway" prompt, or
    /// the fall-through to the URL field when no board answered.
    private(set) var formError: String?
    private(set) var isChecking = false

    private(set) var search: BoardSearch = .idle
    private(set) var selectedBoardID: String?

    /// Set once a check leaves something unconfirmed. The primary button becomes "Save anyway",
    /// which is the spec's escape hatch — the user is told what they're saving before they do.
    private(set) var awaitingConfirmation = false

    /// Guards `load(from:)` so a repeat `onAppear` can't overwrite what the user has typed.
    private var isLoaded = false

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var enteredFieldIndices: [Int] {
        urlFields.indices.filter { !urlFields[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var hasEnteredURL: Bool {
        !enteredFieldIndices.isEmpty
    }

    var isSearching: Bool {
        search == .searching
    }

    /// What the primary button (and `Return`) does next. A name with no URL yet means the user
    /// wants the board found for them, which is the whole point of spec `08`.
    enum SubmitAction {
        case findBoards
        case chooseBoard
        case check
        case saveAnyway
    }

    var submitAction: SubmitAction {
        if awaitingConfirmation { return .saveAnyway }
        if hasEnteredURL { return .check }
        if case .found(let boards) = search, !boards.isEmpty { return .chooseBoard }
        return .findBoards
    }

    var canSubmit: Bool {
        !isChecking && !isSearching && !trimmedName.isEmpty
    }

    var primaryButtonTitle: String {
        switch submitAction {
        case .findBoards: "Find board"
        case .chooseBoard, .check: "Add"
        case .saveAnyway: "Save anyway"
        }
    }

    /// Whether the message under the fields is guidance rather than a blocked action — the
    /// "save anyway" prompt and the no-board fall-through both are, so they don't wear the
    /// accent that spec `06` reserves for something needing attention.
    var formErrorIsAdvisory: Bool {
        awaitingConfirmation || search == .notFound
    }

    // MARK: - Editing

    /// Editing any URL invalidates its check — and with it any pending "save anyway" offer.
    func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.urlFields.first { $0.id == id }?.text ?? ""
            },
            set: { [weak self] newValue in
                guard let self, let index = self.urlFields.firstIndex(where: { $0.id == id }) else { return }
                self.urlFields[index].text = newValue
                self.urlFields[index].outcome = nil
                self.awaitingConfirmation = false
                self.formError = nil
                // Typing over a probed URL leaves the checked row selected, which would be the
                // same lie as a stale green check. The results stay up so it can be re-picked.
                self.selectedBoardID = nil
            }
        )
    }

    func addURLField() {
        urlFields.append(URLField())
        awaitingConfirmation = false
        formError = nil
    }

    func removeURLField(id: UUID) {
        guard urlFields.count > 1 else { return }
        urlFields.removeAll { $0.id == id }
        awaitingConfirmation = false
        formError = nil
    }

    // MARK: - Finding a board by name (spec `08`)

    /// Probes the ATSes for the typed name and shows what answered.
    ///
    /// One hit is pre-selected so `Return` adds it; several are left unselected because
    /// `vercel` genuinely answers on two boards and guessing would be wrong about as often as
    /// it's right. Nothing found falls through to the URL field with a message.
    func findBoards() async {
        guard canSubmit else {
            formError = "Give the company a name."
            return
        }

        search = .searching
        formError = nil
        selectedBoardID = nil

        let boards = await CompanyProbe.probe(name: trimmedName)

        guard !boards.isEmpty else {
            search = .notFound
            formError = "Couldn\u{2019}t find a job board for that name. Paste the careers URL instead."
            return
        }

        search = .found(boards)
        if boards.count == 1 {
            select(boards[0])
        }
    }

    /// Selecting a board fills the first URL field with it, so the chosen result goes through
    /// the same `CompanyURLChecker` path as a pasted URL (spec `08`, "Reuse, don't rebuild")
    /// and the user can see — and edit — exactly what's about to be saved.
    func select(_ board: CompanyBoard) {
        selectedBoardID = board.id
        awaitingConfirmation = false
        formError = nil

        if urlFields.isEmpty {
            urlFields = [URLField(text: board.boardURL)]
        } else {
            urlFields[0].text = board.boardURL
            urlFields[0].outcome = nil
        }
    }

    /// Several boards answered and none is picked: the spec requires the choice.
    func reportBoardChoiceNeeded() {
        formError = "Pick which board to track."
    }

    // MARK: - Checking

    /// Runs detection + the one-shot test fetch for every entered URL.
    ///
    /// Returns true when every URL came back clean, which is the only case that saves without
    /// asking. Anything else leaves the modal open with an explanation (spec `03`).
    func check() async -> Bool {
        // Return fires the field's `onSubmit` *and* the default button, so two checks can be
        // queued before either suspends. Both run on the main actor, so this drops the second.
        guard !isChecking else { return false }
        guard canSubmit else {
            formError = "Give the company a name."
            return false
        }
        guard hasEnteredURL else {
            formError = "Add at least one careers URL."
            return false
        }

        isChecking = true
        formError = nil
        defer { isChecking = false }

        let companyName = trimmedName
        // Addressed by id rather than index: each check suspends, and the rows can be edited
        // while it does.
        let targets = enteredFieldIndices.map { (id: urlFields[$0].id, text: urlFields[$0].text) }

        for target in targets {
            if let index = urlFields.firstIndex(where: { $0.id == target.id }) {
                urlFields[index].isChecking = true
            }
            let outcome = await CompanyURLChecker.check(target.text, companyName: companyName)
            guard let index = urlFields.firstIndex(where: { $0.id == target.id }) else { continue }
            urlFields[index].outcome = outcome
            urlFields[index].isChecking = false
        }

        let outcomes = enteredFieldIndices.compactMap { urlFields[$0].outcome }
        if outcomes.allSatisfy(\.isConfirmed) {
            return true
        }

        // An unparseable URL is never savable, so it blocks rather than offering "save anyway".
        if outcomes.contains(where: { !$0.isSavable }) {
            awaitingConfirmation = false
            formError = "Fix the highlighted URL before adding this company."
        } else {
            awaitingConfirmation = true
            formError = outcomes.contains { if case .unreachable = $0 { true } else { false } }
                ? "Couldn\u{2019}t read this careers page automatically. Save anyway as a generic page?"
                : "Save it anyway and it\u{2019}ll start scraping once its adapter lands."
        }
        return false
    }

    // MARK: - Saving

    /// The classifications to store, in field order.
    ///
    /// A URL that detected fine but wouldn't fetch is downgraded to `generic` — that's the
    /// spec's "save anyway as a generic page," and it keeps us from storing a token we know
    /// doesn't answer. A detected ATS whose adapter simply hasn't been built yet keeps its
    /// type: the classification is right, spec `01` just hasn't reached it.
    var savableDetections: [ATSDetection] {
        enteredFieldIndices.compactMap { index in
            switch urlFields[index].outcome {
            case .reachable(let detection, _), .noAdapterYet(let detection):
                return detection
            case .unreachable(let detection, _):
                return ATSDetection(atsType: .generic, atsToken: nil, normalizedURL: detection.normalizedURL)
            case .invalid, nil:
                return nil
            }
        }
    }

    /// Backstop for the "save anyway" path: the button should never be a silent no-op.
    func reportNothingToSave() {
        awaitingConfirmation = false
        formError = "Nothing here can be saved yet \u{2014} check the careers URL."
    }

    /// Surfaces a storage failure in the modal rather than dismissing over it.
    func reportSaveFailure(_ error: Error) {
        awaitingConfirmation = false
        formError = "Couldn\u{2019}t save this company: \(error.localizedDescription)"
    }

    /// Fills the form from a company already being tracked, for the edit path (spec `08`).
    func load(from company: Company) {
        guard !isLoaded else { return }
        isLoaded = true

        name = company.name
        let fields = company.careerURLs.map { URLField(text: $0) }
        urlFields = fields.isEmpty ? [URLField()] : fields
    }

    /// Writes the checked URLs back onto a company that's already tracked (spec `08`, "Fixing a
    /// wrong URL"). Detection re-ran as part of the check, so a repaired URL updates the ATS
    /// and token with it. Returns false when there's nothing safe to save.
    func apply(to company: Company) -> Bool {
        let detections = savableDetections
        guard !trimmedName.isEmpty, let primary = detections.first else { return false }

        company.name = trimmedName
        company.careerURLs = detections.map(\.normalizedURL)
        company.atsType = primary.atsType
        company.atsToken = primary.atsToken
        return true
    }

    /// Builds the company to insert, or nil if there's nothing safe to save.
    ///
    /// **One classification, several URLs.** §5 gives `Company` a single `atsType`/`atsToken`
    /// while this spec detects per URL, so the company adopts the first URL's classification and
    /// the modal shows every URL's detected ATS — a mismatch is visible rather than silent.
    func makeCompany() -> Company? {
        let detections = savableDetections
        guard !trimmedName.isEmpty, let primary = detections.first else { return nil }

        return Company(
            name: trimmedName,
            careerURLs: detections.map(\.normalizedURL),
            atsType: primary.atsType,
            atsToken: primary.atsToken
        )
    }
}
