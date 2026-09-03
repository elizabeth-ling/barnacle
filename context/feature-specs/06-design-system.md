# Spec 06 — Design System (UI)

Applies to every screen: Feed (`02`), Add-Company modal (`03`), Applied tab + overlay (`05`).

## Direction

Inspired by **Claude** (warm, calm, serif accents, generous but quiet) and **Postman**
(dense, developer-tool efficiency, clear list rows, orange accent). The result should feel
**warm, compact, and precise** — tiny fonts, serif headings, sans-serif body, warm whites and
greys with a single Claude-orange accent.

## Typography

Use Apple's built-in fonts so there's nothing to license and it looks native:

- **Headings → serif:** **New York** (`Font.system(..., design: .serif)`). Apple's system
  serif; matches the "serif headings" request natively.
- **Body / UI → sans-serif:** **SF Pro** (the default system font).

Type scale (intentionally small, per the "tiny font" request):

| Role | Font | Size / weight |
|---|---|---|
| Tab / screen title | New York (serif) | 18pt semibold |
| Section heading, modal title | New York (serif) | 14pt semibold |
| List row — job title / role | SF Pro | 12pt medium |
| Body text | SF Pro | 12pt regular |
| Metadata (company · date · location) | SF Pro | 11pt regular, secondary color |
| Micro labels / badges | SF Pro | 10pt medium, uppercase tracking for "NEW" |

Respect Dynamic Type minimally, but the design target is compact. Don't go below 10pt.

## Color palette

Warm whites and greys with the Claude orange as the only accent.

| Token | Hex | Use |
|---|---|---|
| `bg/primary` | `#FAF9F5` | App background (warm white). |
| `bg/surface` | `#FFFFFF` | Cards, rows, modal/overlay surfaces. |
| `bg/surfaceAlt` | `#F5F4EF` | Hover/selected row, subtle fills. |
| `border/hairline` | `#E7E4DC` | 1px separators, field borders. |
| `text/primary` | `#20201E` | Titles, primary text (warm near-black). |
| `text/secondary` | `#6B6A64` | Company names, dates, metadata (warm grey). |
| `accent` | `#D97757` | Claude orange — buttons, active states, NEW badge. |
| `accent/hover` | `#C25E42` | Pressed/hover accent. |
| `accent/tintBg` | `#F6E9E2` | Very light orange fill behind badges/selection. |

Provide a **dark-mode** variant later if desired, but light warm-white is the primary look
the user asked for. Ship light mode first.

### Status colours (added 2026-09-02)

The one deliberate exception to "orange is the only accent": the Applied tab's five
`ApplicationStatus` values are colour-coded, because status is the thing you scan that list
for. Each is a text colour plus the light fill it sits on — the same relationship `accent`
has with `accent/tintBg` — and all five are desaturated so they read as pills inside the warm
greys rather than competing with them.

| Status | Text | Fill | Notes |
|---|---|---|---|
| `applied` | `#4A6D8C` | `#E7EEF4` | Muted blue — the neutral default state. |
| `interviewing` | `#AD7A26` | `#F7EEDB` | Amber. |
| `offer` | `#4E7A55` | `#E3EDE4` | Reuses the `success` green from spec `03`. |
| `rejected` | `#9E4038` | `#F4E3E0` | Deeper and redder than `accent`, so it can't be misread as one. |
| `ghosted` | `#87827A` | `#EEECE6` | Warm grey. |

These live in `Theme.Palette.Status`; `ApplicationStatus.color` / `.tint` map onto them
(`DesignSystem/StatusStyle.swift`), which also holds the three components that use them:
`StatusBadge`, `StatusDot`, and `StatusSelector`.

## Components & spacing

- **List rows (Feed & Applied):** compact, ~34–40pt tall. Title left-aligned primary;
  company + date as secondary metadata; optional location/status trailing. Full-row hover
  uses `bg/surfaceAlt`. Hairline separators, not heavy dividers. Postman-like density.
- **NEW badge:** small pill or dot in `accent`, or `accent/tintBg` fill with `accent` text,
  10pt uppercase. Sits near the title.
- **Header `+` button:** `accent` fill, white glyph, sized to the quiet controls (same height
  and ~7pt radius), sitting at the end of the screen header's control row. This is each
  screen's primary action.
  *Changed 2026-09-02 at the user's request — it was a floating circle bottom-right with
  ~20pt margins. Putting it beside the filter, sort, and refresh controls keeps every control
  on a screen in one place instead of at opposite corners. `FloatingAddButton` is still in
  the design system, now unused.*
- **Row hover actions:** a control that only makes sense on the row being pointed at — the
  Feed's dismiss `×` — lives in the trailing slot and is in the layout *only* while the row
  is hovered, so the metadata slides over to make room on the standard hover animation.
  `CompactRow` hands its hover state to the trailing builder for exactly this. A permanently
  reserved slot was tried first and rejected: it left a visible gap between the date and the
  row edge on every idle row. *(Added 2026-09-02 with the dismiss feature.)*
- **Buttons:** primary = `accent` fill + white text; secondary = surface + hairline border +
  primary text. Small corner radius (~6–8pt).
- **Modal / overlay surface:** `bg/surface`, ~12pt radius, soft shadow, serif title, tidy
  8–12pt field spacing. The overlay (spec `05`) should feel light and quick — a small card,
  not a full window.
- **Controls row (Feed):** the company filter and sort toggle are quiet — hairline borders,
  secondary text, accent only on the active state. The `+` is the one non-quiet control there.
- **Status pill / dropdown (Applied):** the status name on its own tint, with a 5pt dot and a
  chevron, at the row's trailing edge. Built as a `Menu` with **`.menuStyle(.button)` plus
  `.buttonStyle(.plain)`** — `.borderlessButton` discards the custom label and lets AppKit
  draw its own menu, which is why this chrome never rendered before 2026-09-02.

## Tone

- Restraint over decoration. One accent color, used sparingly.
- Whitespace is calm but the lists are dense — the contrast (airy chrome, tight rows) is the
  Claude-meets-Postman feel.
- Motion: subtle. Fades and small scale on the overlay appear; no bouncy animation.

## Acceptance criteria

- [x] Headings render in a serif (New York); body/UI in SF Pro.
- [x] Palette matches the tokens above; the only accent is Claude orange.
- [x] Feed rows are compact with clear title / metadata hierarchy and a subtle hover.
- [x] The `+` button is an orange control at the end of the screen header's control row.
- [x] A row's hover-only action appears on the hovered row alone and reserves no space at rest.
      *(Was "a floating orange circle, bottom-right" until 2026-09-02.)*
- [x] Each `ApplicationStatus` has its own muted colour, used everywhere status is shown.
- [x] Modal and overlay use the warm surface, serif title, and tiny-font fields.
