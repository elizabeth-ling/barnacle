import AppKit
import Foundation
import Observation
import UserNotifications

/// The consumer of `ScrapeCoordinator.onNewPostings` (spec `04`).
///
/// One scrape run means at most one notification: the coordinator already hands over the whole
/// batch in a single call, and only when the batch is non-empty, so "no notification on a scrape
/// that found nothing new" is structural rather than a check here. Dedup is upstream too — every
/// posting in the batch is genuinely new, so this type never re-filters.
@MainActor
@Observable
final class NotificationService {
    let preferences: NotificationPreferences

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Set when the user clicks a notification, consumed by the Feed via
    /// `takePendingFeedReveal()`. It's consumable rather than plain state because the click can
    /// *launch* the app — the request then has to survive until the Feed first appears, and
    /// apply exactly once when it does.
    private(set) var pendingFeedReveal: FeedRevealRequest?

    @ObservationIgnored private var delegate: NotificationDelegate?
    @ObservationIgnored private var openMainWindow: (() -> Void)?

    init() {
        preferences = NotificationPreferences()
    }

    // MARK: - Setup

    /// Installs the notification delegate and the single-posting category.
    ///
    /// Called from `BarnacleApp.init()`, not from a view's `.task`: clicking a notification while
    /// the app is closed launches it and delivers the response during startup, so the delegate
    /// has to be in place before the app finishes launching or that click is lost.
    func registerNotificationDelegate() {
        let delegate = NotificationDelegate(service: self)
        self.delegate = delegate  // `UNUserNotificationCenter.delegate` is weak.

        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationCategory.singlePosting,
                actions: [
                    // No `.foreground`: this action's destination is the browser, so
                    // activating Barnacle first would only make focus bounce.
                    UNNotificationAction(
                        identifier: NotificationAction.openPosting,
                        title: "Open Posting",
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    /// How the notifier reopens the main window. Registered by the window's own content, because
    /// `openWindow` is only reachable from a `View`; the captured action keeps working after the
    /// window is closed, which is the case that matters for a menu-bar app.
    func registerMainWindowOpener(_ open: @escaping () -> Void) {
        openMainWindow = open
    }

    /// Asks for permission. Safe to call on every launch — the system only shows the prompt the
    /// first time and answers from the stored decision after that.
    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            NotificationLog.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshAuthorizationStatus()
    }

    /// Re-reads the system's answer, so Settings can say when notifications are blocked instead
    /// of showing a toggle that quietly does nothing.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Notifying

    /// The seam: one call per scrape run, carrying that run's whole batch.
    func notify(about postings: [NewPosting]) {
        guard !postings.isEmpty, preferences.isEnabled else { return }

        let title = NotificationSummary.title(for: postings)
        let body = NotificationSummary.body(for: postings)

        postNativeNotification(title: title, body: body, postings: postings)

        // Fired after, and never awaited: the native notification is the guaranteed path, and a
        // dead network or a wrong topic must not affect it.
        if preferences.shouldSendPhonePush {
            sendPhonePush(title: title, body: body)
        }
    }

    private func postNativeNotification(title: String, body: String, postings: [NewPosting]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var userInfo: [String: Any] = [
            NotificationUserInfo.postingIDs: postings.map(\.id.uuidString)
        ]
        if postings.count == 1 {
            // Only a single-posting notification gets the "Open Posting" action — there's no one
            // URL to open for a batch.
            userInfo[NotificationUserInfo.postingURL] = postings[0].url
            content.categoryIdentifier = NotificationCategory.singlePosting
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately.
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NotificationLog.logger.error("Could not post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func sendPhonePush(title: String, body: String) {
        guard let destination = NtfyDestination.url(from: preferences.ntfyTopic) else { return }
        Task {
            do {
                try await NtfyClient.send(title: title, body: body, to: destination)
            } catch {
                NotificationLog.logger.error("ntfy push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Publishes a one-off message so the user can confirm their topic reaches their phone
    /// without waiting for a real scrape. Throws so Settings can show what went wrong.
    func sendTestPhonePush() async throws {
        guard let destination = NtfyDestination.url(from: preferences.ntfyTopic) else {
            throw NtfyError.invalidDestination(preferences.ntfyTopic)
        }
        try await NtfyClient.send(
            title: "Barnacle is connected",
            body: "New internships will arrive here.",
            to: destination
        )
    }

    // MARK: - Responding to a click

    func handleResponse(actionIdentifier: String, postingIDs: [UUID], postingURL: String?) {
        if actionIdentifier == NotificationAction.openPosting {
            if let postingURL, let url = URL(string: postingURL) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        // Everything else that isn't an explicit dismiss counts as "the user clicked the body".
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        NSApp.activate(ignoringOtherApps: true)
        openMainWindow?()

        if !postingIDs.isEmpty {
            pendingFeedReveal = FeedRevealRequest(postingIDs: postingIDs)
        }
    }

    /// Reading the reveal clears it, so it applies exactly once.
    func takePendingFeedReveal() -> FeedRevealRequest? {
        defer { pendingFeedReveal = nil }
        return pendingFeedReveal
    }
}

/// The Feed items a clicked notification was about. Carries a fresh `id` so two clicks on
/// notifications covering the same postings still read as two separate requests.
struct FeedRevealRequest: Identifiable, Equatable {
    let id = UUID()
    let postingIDs: [UUID]
}

enum NotificationCategory {
    static let singlePosting = "barnacle.notification.singlePosting"
}

enum NotificationAction {
    static let openPosting = "barnacle.notification.openPosting"
}

enum NotificationUserInfo {
    static let postingIDs = "barnacle.postingIDs"
    static let postingURL = "barnacle.postingURL"
}

/// Bridges `UNUserNotificationCenter`'s ObjC delegate onto the main-actor service.
///
/// Separate from `NotificationService` so the service can stay a plain `@Observable` main-actor
/// type: the delegate callbacks arrive off the main actor, and the values they carry
/// (`UNNotificationResponse`, `userInfo`) can't cross actors, so they're unpacked here first.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var service: NotificationService?

    init(service: NotificationService) {
        self.service = service
    }

    /// Show the banner even when Barnacle is frontmost — the user may be on the Applied tab, or
    /// have the window buried behind another app while it's still the active one.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let postingIDs = (userInfo[NotificationUserInfo.postingIDs] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        let postingURL = userInfo[NotificationUserInfo.postingURL] as? String
        let actionIdentifier = response.actionIdentifier
        let service = self.service

        Task { @MainActor in
            service?.handleResponse(
                actionIdentifier: actionIdentifier,
                postingIDs: postingIDs,
                postingURL: postingURL
            )
            completionHandler()
        }
    }
}
