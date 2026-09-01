import Foundation
import Observation

/// The user's notification settings (spec `04`), backed by `UserDefaults`.
///
/// Not `@AppStorage`: `NotificationService` reads these outside any view, and both it and
/// `SettingsView` have to see the same values. One observable object owns them instead, so a
/// toggle in Settings takes effect on the very next scrape without a restart.
@MainActor
@Observable
final class NotificationPreferences {
    /// Master switch. Off silences the phone push too — turning notifications off and still
    /// having a phone buzz would be the surprising reading.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Off by default, as the spec requires: the phone path needs the ntfy iOS app first.
    var isPhonePushEnabled: Bool {
        didSet { defaults.set(isPhonePushEnabled, forKey: Key.isPhonePushEnabled) }
    }

    /// Either a bare topic (`barnacle-a1b2…`, published to ntfy.sh) or a full server URL for
    /// self-hosters. `NtfyDestination` resolves whichever the user typed.
    var ntfyTopic: String {
        didSet { defaults.set(ntfyTopic, forKey: Key.ntfyTopic) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` rather than `bool(forKey:)` so an unset master switch defaults to
        // on — `bool(forKey:)` would report false and silence a fresh install.
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        isPhonePushEnabled = defaults.object(forKey: Key.isPhonePushEnabled) as? Bool ?? false
        ntfyTopic = defaults.string(forKey: Key.ntfyTopic) ?? ""
    }

    /// Whether a batch should also go out over ntfy. The master switch gates this.
    var shouldSendPhonePush: Bool {
        isEnabled && isPhonePushEnabled && NtfyDestination.url(from: ntfyTopic) != nil
    }

    private enum Key {
        static let isEnabled = "notifications.enabled"
        static let isPhonePushEnabled = "notifications.phone.enabled"
        static let ntfyTopic = "notifications.ntfy.topic"
    }
}
