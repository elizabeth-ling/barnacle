import AppKit
import HotKey
import Observation
import OSLog
import SwiftData
import SwiftUI

/// The global `⌘J` overlay (spec `05`) — the feature the native-macOS choice was made for.
///
/// Owns the hotkey and the floating panel, and nothing else: the form inside it is the same
/// `ApplicationFormView` the Applied tab's sheet uses.
///
/// Lives on the app, not on a view, so it keeps working with every window closed — Barnacle
/// stays alive in the menu bar (§8), which is what makes a *global* hotkey possible at all.
@MainActor
@Observable
final class QuickAddOverlay {
    private let container: ModelContainer

    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var panel: QuickAddPanel?
    @ObservationIgnored private var panelDelegate: PanelDelegate?

    /// Whoever was in front when the overlay opened, so focus can go back there on dismiss.
    /// Weak: the app underneath can quit while the overlay is up.
    @ObservationIgnored private weak var previousApp: NSRunningApplication?

    /// Where the panel's top-left sits, so content that grows (the company suggestions) pushes
    /// the panel downward instead of walking it up the screen.
    @ObservationIgnored private var anchorTopLeft: NSPoint?

    /// Set while the app is masquerading as an accessory for the life of the panel.
    @ObservationIgnored private var restoreRegularPolicy = false

    private static let width: CGFloat = 420
    /// Room around the card for its shadow — the panel itself is transparent and shadowless.
    private static let shadowMargin: CGFloat = 16

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Hotkey

    /// Registers `⌘J` system-wide.
    ///
    /// `HotKey` wraps Carbon's `RegisterEventHotKey`, which needs no Accessibility permission —
    /// an event-tap approach would, and spec `05` prefers the Carbon path for exactly that
    /// reason. Registration is idempotent so a second `start()` can't double-fire the handler.
    func start() {
        guard hotKey == nil else { return }

        // The label is not optional noise: a bare trailing closure binds to `keyUpHandler`,
        // which would fire the overlay on the release of ⌘J instead of the press.
        hotKey = HotKey(key: .j, modifiers: [.command], keyDownHandler: { [weak self] in
            // Carbon delivers this on the main thread, but hop explicitly rather than assume it
            // — a wrong assumption here would trap instead of just being late.
            Task { @MainActor in self?.toggle() }
        })

        OverlayLog.logger.info("Registered the global \u{2318}J hotkey")
    }

    // MARK: - Showing and hiding

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Only remember an app that isn't us: pressing ⌘J inside Barnacle shouldn't teach the
        // overlay to "return focus" to the window it's already floating over.
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmost

        let panel = panel ?? makePanel()
        self.panel = panel

        // A fresh hosting controller per show: the overlay is meant to open empty with the
        // company field focused, and rebuilding is what resets SwiftUI's state and re-fires
        // `onAppear`. Reusing one would reopen it holding the last thing that was typed.
        panel.contentViewController = makeContentController()
        panel.layoutIfNeeded()

        position(panel)

        // ⌘J pressed inside Barnacle: the app is already active, so the panel only has to take
        // key status. Running the activation dance below from here instead makes AppKit tear
        // the panel straight back down — it never gets as far as being visible.
        guard !NSApp.isActive else {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        // Getting a floating panel over a full-screen Space *and* able to type into it takes
        // all three of these, in this order:
        //
        // 1. `.accessory` for the life of the panel. A key window only receives keystrokes
        //    while its app is active, so the app has to activate — but activating a *regular*
        //    app makes macOS reveal the Space its ordinary windows live on, which is the Space
        //    switch this whole feature exists to avoid. Accessory apps carry no such
        //    obligation. (It is why the launcher apps that do this are accessory full-time;
        //    Barnacle only borrows it while the panel is up, and is `.regular` again after.)
        // 2. Order the panel front first, so activation has a window of ours already on the
        //    current Space to hand key status to.
        // 3. Activate, then make the panel key. `.nonactivatingPanel` keeps this from pulling
        //    Barnacle's other windows forward — the app is active, but nothing moves.
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
            restoreRegularPolicy = true
        }
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKey()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }

        panel.orderOut(nil)
        // Dropping the content view controller releases the SwiftUI form (and its queries)
        // rather than leaving it observing the store while the panel is out of sight.
        panel.contentViewController = nil
        anchorTopLeft = nil

        // Showing the panel activated Barnacle (see `show()`), so put the user back where they
        // were before restoring the activation policy — a `.regular` app that is still active
        // is exactly the state that would pull the Space over to Barnacle's own windows.
        if NSApp.isActive, let previousApp, previousApp != .current {
            previousApp.activate()
        }
        previousApp = nil

        // Back to a normal app: the Dock icon and the app menu return with it.
        if restoreRegularPolicy {
            NSApp.setActivationPolicy(.regular)
            restoreRegularPolicy = false
        }
    }

    // MARK: - Panel

    private func makePanel() -> QuickAddPanel {
        let panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            // `.nonactivatingPanel` is the load-bearing one: showing the panel must not steal
            // activation from the full-screen app underneath.
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        // These three together are what put the panel over another app's full-screen Space.
        // Without `.fullScreenAuxiliary` it simply will not appear there; without
        // `.canJoinAllSpaces` it drags the user back to the Space it was opened on.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Barnacle is never the active app while this is up, so a panel that hides on
        // deactivation would never be visible at all.
        panel.hidesOnDeactivate = false

        // Chrome-less: the card inside draws the surface, radius, and shadow (spec `06`).
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .utilityWindow
        // The palette is fixed light values — the same light-only caveat as `RootView`.
        panel.appearance = NSAppearance(named: .aqua)

        panel.onCancel = { [weak self] in self?.hide() }

        let delegate = PanelDelegate(overlay: self)
        panelDelegate = delegate  // `NSWindow.delegate` is weak.
        panel.delegate = delegate

        return panel
    }

    private func makeContentController() -> NSViewController {
        let content = QuickAddView(
            onCancel: { [weak self] in self?.hide() },
            onSaved: { [weak self] in self?.hide() }
        )
        .frame(width: Self.width)
        .padding(Self.shadowMargin)
        .modelContainer(container)

        let controller = NSHostingController(rootView: content)
        // Lets the panel follow the form's height as the company suggestions appear and go.
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    /// Centers horizontally and sits a little above centre — high enough to read at a glance,
    /// low enough not to collide with the menu bar — on whichever screen the pointer is on.
    private func position(_ panel: QuickAddPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? panel.screen
            ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        // Clamped so a tall form (or a short screen) can't push the panel off the top or the
        // side — `setFrameTopLeftPoint` would happily place it under the menu bar.
        let topLeft = NSPoint(
            x: min(max(visibleFrame.midX - size.width / 2, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(visibleFrame.midY + size.height / 2 + visibleFrame.height * 0.12, visibleFrame.maxY)
        )

        anchorTopLeft = topLeft
        panel.setFrameTopLeftPoint(topLeft)
    }

    /// Keeps the top edge put while the form grows or shrinks under it.
    fileprivate func panelDidResize() {
        guard let panel, let anchorTopLeft else { return }
        panel.setFrameTopLeftPoint(anchorTopLeft)
    }

    /// Losing key status means the user clicked something else — the spec's "click outside".
    fileprivate func panelDidResignKey() {
        hide()
    }
}

/// Split out because `QuickAddOverlay` is `@MainActor` and `@Observable`, and `NSWindowDelegate`
/// conformance on it would drag both into AppKit's non-isolated protocol.
private final class PanelDelegate: NSObject, NSWindowDelegate {
    private weak var overlay: QuickAddOverlay?

    init(overlay: QuickAddOverlay) {
        self.overlay = overlay
    }

    func windowDidResize(_ notification: Notification) {
        MainActor.assumeIsolated { overlay?.panelDidResize() }
    }

    func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { overlay?.panelDidResignKey() }
    }
}

enum OverlayLog {
    static let logger = Logger(subsystem: "com.elizabeth.barnacle", category: "overlay")
}
