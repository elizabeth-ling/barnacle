import SwiftUI

/// Design tokens (spec `06`). Every screen draws color, type, and spacing from here so the
/// Feed (`02`), add-company modal (`03`), and Applied tab + overlay (`05`) read as one system:
/// warm, compact, precise — Claude's calm serif chrome over Postman's dense rows.
///
/// The palette is fixed light warm-white; the spec defers a dark variant, so `RootView` pins the
/// window to `.light` rather than letting these values land on dark system chrome.
enum Theme {
    /// Warm whites and greys with Claude orange as the only accent.
    enum Palette {
        /// `bg/primary` — app background.
        static let background = Color(hex: 0xFAF9F5)
        /// `bg/surface` — cards, rows, modal and overlay surfaces.
        static let surface = Color(hex: 0xFFFFFF)
        /// `bg/surfaceAlt` — hover/selected row, subtle fills.
        static let surfaceAlt = Color(hex: 0xF5F4EF)
        /// `border/hairline` — 1px separators, field borders.
        static let hairline = Color(hex: 0xE7E4DC)
        /// `text/primary` — titles and primary text (warm near-black).
        static let textPrimary = Color(hex: 0x20201E)
        /// `text/secondary` — company names, dates, metadata (warm grey).
        static let textSecondary = Color(hex: 0x6B6A64)
        /// `accent` — Claude orange. The only accent; use it sparingly.
        static let accent = Color(hex: 0xD97757)
        /// `accent/hover` — pressed/hover accent.
        static let accentHover = Color(hex: 0xC25E42)
        /// `accent/tintBg` — very light orange fill behind badges and selection.
        static let accentTint = Color(hex: 0xF6E9E2)
        /// The one non-accent hue in the palette: spec `03` asks for a green check on a careers
        /// URL that validated. Muted to sit beside the warm greys rather than shout over them.
        static let success = Color(hex: 0x4E7A55)
    }

    /// Serif headings (New York, via `design: .serif`), SF Pro for body and UI. Sizes are
    /// deliberately small — the design target is compact — and nothing goes below 10pt.
    enum Typography {
        /// Tab / screen title.
        static let screenTitle = Font.system(size: 18, weight: .semibold, design: .serif)
        /// Section heading, modal title.
        static let sectionTitle = Font.system(size: 14, weight: .semibold, design: .serif)
        /// List row — job title / role.
        static let rowTitle = Font.system(size: 12, weight: .medium)
        /// Body text, field text, buttons.
        static let body = Font.system(size: 12)
        /// Metadata: company · date · location.
        static let metadata = Font.system(size: 11)
        /// Micro labels and badges. Uppercase it and apply `microLabelTracking`.
        static let microLabel = Font.system(size: 10, weight: .medium)
        /// Letter spacing for the uppercase micro labels ("NEW").
        static let microLabelTracking: CGFloat = 0.6
    }

    /// Spacing, sizing, and the two shadows. Dense rows inside airy chrome.
    enum Metrics {
        /// Compact list row height (spec: ~34–40pt).
        static let rowMinHeight: CGFloat = 36
        static let rowHorizontalPadding: CGFloat = 12
        static let rowVerticalPadding: CGFloat = 6
        /// Outer padding for screen chrome — headers, controls rows, empty states.
        static let screenPadding: CGFloat = 16
        /// Buttons and quiet controls.
        static let controlRadius: CGFloat = 7
        /// Cards, modals, the `⌘J` overlay.
        static let surfaceRadius: CGFloat = 12
        /// Vertical rhythm between fields in a modal or overlay (spec: 8–12pt).
        static let fieldSpacing: CGFloat = 10
        static let floatingButtonSize: CGFloat = 40
        static let floatingButtonMargin: CGFloat = 20

        /// Soft shadow under modals, overlays, and the floating `+`.
        static let shadowColor = Color.black.opacity(0.12)
        static let shadowRadius: CGFloat = 10
        static let shadowOffsetY: CGFloat = 3

        /// Fades and small scales only — no bouncy animation anywhere.
        static let hoverAnimation = Animation.easeOut(duration: 0.12)
    }
}

private extension Color {
    /// `0xRRGGBB` literal to a fixed sRGB color. Tokens are light-mode values by design; when a
    /// dark variant lands these move to an asset catalog with per-appearance colors.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
