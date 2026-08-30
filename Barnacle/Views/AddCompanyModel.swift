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

    var name = ""
    var urlFields: [URLField] = [URLField()]

    /// The single message under the fields: what's missing, or the spec's "save anyway" prompt.
    private(set) var formError: String?
    private(set) var isChecking = false

    /// Set once a check leaves something unconfirmed. The primary button becomes "Save anyway",
    /// which is the spec's escape hatch — the user is told what they're saving before they do.
    private(set) var awaitingConfirmation = false

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var enteredFieldIndices: [Int] {
        urlFields.indices.filter { !urlFields[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var canSubmit: Bool {
        !isChecking && !trimmedName.isEmpty && !enteredFieldIndices.isEmpty
    }

    var primaryButtonTitle: String {
        awaitingConfirmation ? "Save anyway" : "Add"
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
            formError = trimmedName.isEmpty
                ? "Give the company a name."
                : "Add at least one careers URL."
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
