import Foundation

/// What kind of role the user is looking for (spec `07`).
///
/// An enum rather than a pair of bools: internship and new grad are mutually exclusive in
/// practice, and an enum makes "neither selected" unrepresentable. This is a setting, not a
/// filter — it changes once, at graduation.
enum RoleLevel: String, CaseIterable, Sendable, Identifiable {
    case internship
    case newGrad

    var id: String { rawValue }

    /// Label for the Settings segmented control.
    var displayName: String {
        switch self {
        case .internship: "Internships"
        case .newGrad: "New grad"
        }
    }

    /// Reads as "47 internship postings" in the purge dialog.
    var postingNoun: String {
        switch self {
        case .internship: "internship"
        case .newGrad: "new-grad"
        }
    }
}

/// The one place that decides whether a title is the kind of role the user wants (§6, spec `07`).
///
/// Replaces `InternshipFilter`, and keeps its whole-word rule. Adapters no longer call this:
/// the filter runs once in `ScrapeRunner`, so reconciliation can still tell "gone from the
/// source" from "no longer matches your settings" (spec `07`).
enum RoleLevelFilter {
    /// `intern` alone already catches "intern" and "interns"; `internship` earns its own entry
    /// under the whole-word rule, and the co-op spellings are listed because some companies use
    /// that term instead.
    static let internshipKeywords = ["intern", "internship", "co-op", "co op", "coop"]

    /// The new-grad vocabulary. `graduate` is deliberately in here despite being the weakest
    /// signal — boards do title roles "Graduate Software Engineer" — and `newGradExclusions`
    /// is what keeps it honest.
    static let newGradKeywords = [
        "new grad", "new graduate", "university grad", "university graduate",
        "entry level", "entry-level", "early career", "campus", "graduate",
    ]

    /// Applied *after* a new-grad keyword matched. `graduate` and `campus` repeat §6's exact
    /// trap: they match "Graduate Program Manager" and "Campus Recruiter", which are the jobs
    /// that hire new grads rather than the jobs new grads take. A title matching any of these
    /// is rejected however well it matched.
    static let newGradExclusions = [
        "program manager", "recruiter", "recruiting", "coordinator",
        "director", "manager", "lead", "senior", "staff", "principal",
    ]

    static func keywords(for level: RoleLevel) -> [String] {
        switch level {
        case .internship: internshipKeywords
        case .newGrad: newGradKeywords
        }
    }

    /// Whether a posting title is the role level the user asked for.
    ///
    /// Keywords match whole words (plus an optional plural `s`), not bare substrings. A plain
    /// `contains` check reads "Internal Audit Lead" as an internship — real boards are full of
    /// those, and they'd land in the feed and fire notifications. Word boundaries drop them
    /// while still catching "Intern", "Interns", "Internship", and the co-op spellings.
    static func matches(title: String, level: RoleLevel) -> Bool {
        let lowercased = title.lowercased()
        guard keywords(for: level).contains(where: { containsWholeWord($0, in: lowercased) }) else {
            return false
        }
        if level == .newGrad, newGradExclusions.contains(where: { containsWholeWord($0, in: lowercased) }) {
            return false
        }
        return true
    }

    private static func containsWholeWord(_ keyword: String, in lowercasedTitle: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))s?\\b"
        return lowercasedTitle.range(of: pattern, options: .regularExpression) != nil
    }
}
