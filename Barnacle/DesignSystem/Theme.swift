import SwiftUI

/// Design tokens (spec `06`). Every screen draws color, type, and spacing from here so the
/// Feed (`02`), add-company modal (`03`), and Applied tab + overlay (`05`) read as one system:
/// calm, compact, precise — taken from the app icon's one teal mark on white, over dense rows.
///
/// The palette is fixed light off-white; the spec defers a dark variant, so `RootView` pins the
/// window to `.light` rather than letting these values land on dark system chrome.
enum Theme {
    /// Cool off-whites and greys, faintly tinted toward the icon's teal, which is the only accent.
    enum Palette {
        /// `bg/primary` — app background.
        static let background = Color(hex: 0xF7F9F9)
        /// `bg/surface` — cards, rows, modal and overlay surfaces.
        static let surface = Color(hex: 0xFFFFFF)
        /// `bg/surfaceAlt` — hover/selected row, subtle fills.
        static let surfaceAlt = Color(hex: 0xEFF4F4)
        /// `border/hairline` — 1px separators, field borders.
        static let hairline = Color(hex: 0xDDE5E5)
        /// `text/primary` — titles and primary text (cool near-black).
        static let textPrimary = Color(hex: 0x1D2424)
        /// `text/secondary` — company names, dates, metadata (cool grey).
        static let textSecondary = Color(hex: 0x5E6A6B)
        /// `accent` — the app icon's teal, exactly. The only accent; use it sparingly. For fills,
        /// strokes, and glyphs; text takes `accentText`.
        static let accent = Color(hex: 0x619B9D)
        /// `accent/hover` — pressed/hover accent.
        static let accentHover = Color(hex: 0x4F8789)
        /// `accent/text` — accent as small type. The icon's teal is only 2.7:1 on its own tint,
        /// too light for 10–12pt labels; this is the same hue at 4.9:1.
        static let accentText = Color(hex: 0x3B6F71)
        /// `accent/tintBg` — very light teal fill behind badges and selection.
        static let accentTint = Color(hex: 0xE5F0F0)
        /// Errors and warnings. Separate from the accent because teal reads as "fine", so a
        /// failure drawn in it wouldn't look like one. Same brick red as `Status.rejected`.
        static let danger = Color(hex: 0x9E4038)
        /// The light fill `danger` sits on, for warning banners.
        static let dangerTint = Color(hex: 0xF4E3E0)
        /// Spec `03` asks for a green check on a careers URL that validated. Muted to sit beside
        /// the cool greys rather than shout over them.
        static let success = Color(hex: 0x4E7A55)

        /// One muted hue per `ApplicationStatus`, so the Applied tab reads at a glance. Each is
        /// a text color plus the light fill it sits on, in the same relationship the accent has
        /// with `accentTint`. Kept desaturated on purpose — the greys are still the page, and
        /// these are pills inside it. `ApplicationStatus.color` / `.tint` map onto them.
        enum Status {
            static let applied = Color(hex: 0x4A6D8C)
            static let appliedTint = Color(hex: 0xE7EEF4)
            static let interviewing = Color(hex: 0xAD7A26)
            static let interviewingTint = Color(hex: 0xF7EEDB)
            /// Reuses the `success` green — an offer is the good ending.
            static let offer = Color(hex: 0x4E7A55)
            static let offerTint = Color(hex: 0xE3EDE4)
            /// Reuses `danger` — a rejection is the bad ending.
            static let rejected = danger
            static let rejectedTint = dangerTint
            static let ghosted = Color(hex: 0x7A8485)
            static let ghostedTint = Color(hex: 0xE9EEEE)
        }
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
