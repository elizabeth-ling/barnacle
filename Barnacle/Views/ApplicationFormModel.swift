import Foundation
import Observation
import SwiftData

/// The editable state behind the one application form (spec `05`).
///
/// The Applied tab's "+ Add application" sheet and the global `⌘J` overlay are the same view
/// over this model, so there is a single creation path no matter where the user starts — which
/// is what the spec asks for, and what keeps the two surfaces from drifting apart.
@MainActor
@Observable
final class ApplicationFormModel: Identifiable {
    /// Identity for `.sheet(item:)`: presenting the sheet *is* creating the model, so the sheet
    /// re-opens fresh for every add and every edit.
    let id = UUID()

    /// Creating is deliberately the smaller form. The overlay exists to be typed through in a
    /// couple of seconds, so `dateApplied` and `status` take their defaults (now, `applied`)
    /// and are edited later in the Applied tab — which is where editing exposes them.
    enum Mode {
        case create
        case edit(Application)
    }

    let mode: Mode

    var companyName = ""
    var jobTitle = ""
    var url = ""
    var notes = ""
    var dateApplied = Date()
    var status: ApplicationStatus = .applied

    /// Why the last submit didn't go through. Nil the rest of the time.
    private(set) var errorMessage: String?

    init(mode: Mode = .create) {
        self.mode = mode

        if case .edit(let application) = mode {
            companyName = application.companyName
            jobTitle = application.jobTitle
            url = application.url ?? ""
            notes = application.notes ?? ""
            dateApplied = application.dateApplied
            status = application.status
        }
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var title: String { isEditing ? "Edit application" : "Log application" }
    var submitTitle: String { isEditing ? "Save" : "Log it" }

    var trimmedCompanyName: String { companyName.trimmed }
    var trimmedJobTitle: String { jobTitle.trimmed }

    /// Both required fields carry content. The URL is optional and never blocks a save.
    var canSubmit: Bool {
        !trimmedCompanyName.isEmpty && !trimmedJobTitle.isEmpty
    }

    /// Ranks known company names against what's typed so far: tracked companies first-class,
    /// names already used on an application just as good, prefix matches before substring ones.
    ///
    /// Case-insensitive throughout, and a name the user has already typed in full is dropped —
    /// suggesting what's already in the field is noise.
    func suggestions(from names: [String], limit: Int = 4) -> [String] {
        let typed = trimmedCompanyName.lowercased()
        guard !typed.isEmpty else { return [] }

        var seen = Set<String>()
        let unique = names
            .map { $0.trimmed }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        let matches = unique.compactMap { name -> (name: String, isPrefix: Bool)? in
            let lowered = name.lowercased()
            guard lowered != typed else { return nil }
            if lowered.hasPrefix(typed) { return (name, true) }
            if lowered.contains(typed) { return (name, false) }
            return nil
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.name)
    }

    func acceptSuggestion(_ name: String) {
        companyName = name
        errorMessage = nil
    }

    // MARK: - Saving

    /// Inserts (or updates) the application and commits it.
    ///
    /// Returns false — leaving a message behind — when there's nothing valid to save or the
    /// store refused it, so callers keep the form open instead of dismissing over lost typing.
    @discardableResult
    func save(in context: ModelContext) -> Bool {
        guard canSubmit else {
            errorMessage = "Company and role are both required."
            return false
        }

        let inserted: Application?

        switch mode {
        case .create:
            let application = Application(
                companyName: trimmedCompanyName,
                jobTitle: trimmedJobTitle,
                url: normalizedURL,
                dateApplied: dateApplied,
                status: status,
                notes: notes.trimmed.nilIfEmpty
            )
            context.insert(application)
            inserted = application

        case .edit(let application):
            application.companyName = trimmedCompanyName
            application.jobTitle = trimmedJobTitle
            application.url = normalizedURL
            application.dateApplied = dateApplied
            application.status = status
            application.notes = notes.trimmed.nilIfEmpty
            inserted = nil
        }

        do {
            try context.save()
        } catch {
            // A failed insert is undone; a failed edit is left alone rather than rolled back,
            // because `rollback()` would also discard unrelated pending changes on the shared
            // context (a posting's `viewedAt`, say).
            if let inserted { context.delete(inserted) }
            errorMessage = "Couldn\u{2019}t save this application: \(error.localizedDescription)"
            return false
        }

        errorMessage = nil
        return true
    }

    /// Stored with a scheme so the Applied tab can hand it straight to the browser — people
    /// paste "jobs.acme.com/123" as often as they paste the full thing.
    private var normalizedURL: String? {
        let text = url.trimmed
        guard !text.isEmpty else { return nil }
        return text.contains("://") ? text : "https://" + text
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
