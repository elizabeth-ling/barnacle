import Foundation
import Observation

/// The settings that decide what gets stored (spec `07`), as one `Sendable` value.
///
/// `ScrapeRunner` is an actor and `ScrapePreferences` is main-actor state, so the coordinator
/// reads the settings on the main actor and hands the runner this snapshot for the run. Every
/// consumer therefore filters against the same values for the whole pass.
struct ScrapeFilter: Sendable, Equatable {
    var roleLevel: RoleLevel
    var countries: Set<String>
    var includeUnknownLocation: Bool

    /// Internships in the US and Canada, unknown locations kept (spec `07`).
    static let `default` = ScrapeFilter(
        roleLevel: .internship,
        countries: ["US", "CA"],
        includeUnknownLocation: true
    )

    /// The stored settings, read straight from `UserDefaults`.
    ///
    /// `object(forKey:)` rather than `bool(forKey:)`: an unset key reads as `false` there, which
    /// would silently strangle a fresh install by dropping every unknown-location posting.
    static func stored(in defaults: UserDefaults = .standard) -> ScrapeFilter {
        var filter = ScrapeFilter.default
        if let raw = defaults.string(forKey: Key.roleLevel), let level = RoleLevel(rawValue: raw) {
            filter.roleLevel = level
        }
        if let codes = defaults.array(forKey: Key.countries) as? [String] {
            filter.countries = Set(codes)
        }
        if let include = defaults.object(forKey: Key.includeUnknownLocation) as? Bool {
            filter.includeUnknownLocation = include
        }
        return filter
    }

    /// Whether the title is the kind of role the user is looking for.
    func admits(title: String) -> Bool {
        RoleLevelFilter.matches(title: title, level: roleLevel)
    }

    /// **Reject only on a confident non-match.** A posting is dropped only if every part of its
    /// location resolved *and* none of them is a country the user watches. Anything unknown is
    /// kept, because at scrape time a misclassification isn't a filter you can flip off — the
    /// posting is never stored and never seen, and a San Francisco internship missed because the
    /// board wrote something unusual is the one failure that costs a job.
    func admits(_ location: LocationClassifier.Match) -> Bool {
        // No countries chosen is "no country restriction" rather than a feed that can never
        // fill: the picker can be emptied, and an empty feed would be a baffling result.
        guard !countries.isEmpty else { return true }
        if !location.countries.isDisjoint(with: countries) { return true }
        if location.hasUnknown { return includeUnknownLocation }
        return false
    }

    enum Key {
        static let roleLevel = "scrape.roleLevel"
        static let countries = "scrape.countries"
        static let includeUnknownLocation = "scrape.includeUnknownLocation"
        static let didBackfillRegions = "scrape.didBackfillRegions"
    }
}

/// The user's role-level and location settings (spec `07`), backed by `UserDefaults`.
///
/// Not `@AppStorage`, for the same reason as `NotificationPreferences`: `ScrapeRunner` reads
/// these outside any view, and it and `SettingsView` must see the same values — so a change
/// takes effect on the next scrape with no restart.
@MainActor
@Observable
final class ScrapePreferences {
    var roleLevel: RoleLevel {
        didSet { defaults.set(roleLevel.rawValue, forKey: ScrapeFilter.Key.roleLevel) }
    }

    /// ISO 3166-1 alpha-2 codes. Stored as an array — `UserDefaults` has no set.
    var countries: Set<String> {
        didSet { defaults.set(countries.sorted(), forKey: ScrapeFilter.Key.countries) }
    }

    var includeUnknownLocation: Bool {
        didSet { defaults.set(includeUnknownLocation, forKey: ScrapeFilter.Key.includeUnknownLocation) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = ScrapeFilter.stored(in: defaults)
        roleLevel = stored.roleLevel
        countries = stored.countries
        includeUnknownLocation = stored.includeUnknownLocation
    }

    /// The snapshot the scrape pass filters against.
    var filter: ScrapeFilter {
        ScrapeFilter(
            roleLevel: roleLevel,
            countries: countries,
            includeUnknownLocation: includeUnknownLocation
        )
    }

    /// Whether the one-time region backfill has run (spec `07`).
    var didBackfillRegions: Bool {
        get { defaults.bool(forKey: ScrapeFilter.Key.didBackfillRegions) }
        set { defaults.set(newValue, forKey: ScrapeFilter.Key.didBackfillRegions) }
    }
}
