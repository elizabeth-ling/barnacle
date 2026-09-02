import AppKit

/// The window behind the global `⌘J` overlay (spec `05`).
///
/// An `NSPanel` rather than an `NSWindow`, and specifically a **non-activating** one: it has to
/// float in front of whatever the user is doing — including another app's full-screen Space —
/// take keystrokes immediately, and pull none of Barnacle's other windows forward while it does.
/// That configuration lives in `QuickAddOverlay.makePanel()` and `show()`; this subclass only
/// supplies the two things that must be overridden rather than set.
final class QuickAddPanel: NSPanel {
    /// Panels are not key-eligible by default, and the entire point of this one is typing into
    /// it the moment it appears.
    override var canBecomeKey: Bool { true }

    /// Main status belongs to the real window. Becoming main is what would make this feel like
    /// switching apps, which is what the overlay exists to avoid.
    override var canBecomeMain: Bool { false }

    /// Esc, wherever the responder chain hands it off — the text fields consume it first when
    /// they're mid-edit, so this is the fallback for the rest of the panel.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
