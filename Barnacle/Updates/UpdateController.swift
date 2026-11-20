import Foundation
import Observation
import Sparkle

/// Owns Sparkle (spec `12`): the daily check against the appcast on GitHub Releases, the
/// background download, and the install when Barnacle next quits.
///
/// **Sparkle owns the setting; this only mirrors it.** Whether updates install by themselves is
/// Sparkle's `SUAutomaticallyUpdate` default — `Info.plist` makes it on, and onboarding or
/// Settings may turn it off. Keeping a second copy in `UserDefaults` would be one that could
/// disagree with what Sparkle actually does.
@MainActor
@Observable
final class UpdateController {
    /// On: downloaded quietly, installed the next time Barnacle quits. Off: Sparkle still checks
    /// daily, but shows its "A new version is available" dialog and waits to be asked.
    var installsAutomatically: Bool {
        didSet {
            guard installsAutomatically != updater.automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = installsAutomatically
        }
    }

    /// False while a check is already running, and always false in Debug.
    private(set) var canCheckForUpdates = false

    /// Debug builds never start the updater: one would offer to replace the copy Xcode just
    /// built with whatever is on the Releases page.
    let isActive: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater { controller.updater }

    init() {
        #if DEBUG
        let isActive = false
        #else
        let isActive = true
        #endif

        controller = SPUStandardUpdaterController(
            startingUpdater: isActive,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.isActive = isActive
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates

        // Sparkle changes this on the main thread; the hop only satisfies the compiler.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    /// The user-initiated check: Sparkle shows its own window either way — "You're up to date"
    /// or the update with its release notes.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
