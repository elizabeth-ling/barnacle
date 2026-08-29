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

## Components & spacing

- **List rows (Feed & Applied):** compact, ~34–40pt tall. Title left-aligned primary;
  company + date as secondary metadata; optional location/status trailing. Full-row hover
  uses `bg/surfaceAlt`. Hairline separators, not heavy dividers. Postman-like density.
- **NEW badge:** small pill or dot in `accent`, or `accent/tintBg` fill with `accent` text,
  10pt uppercase. Sits near the title.
- **Floating `+` button:** circular, `accent` fill, white glyph, soft shadow, bottom-right
  with ~20pt margins. This is the Feed's primary action.
- **Buttons:** primary = `accent` fill + white text; secondary = surface + hairline border +
  primary text. Small corner radius (~6–8pt).
- **Modal / overlay surface:** `bg/surface`, ~12pt radius, soft shadow, serif title, tidy
  8–12pt field spacing. The overlay (spec `05`) should feel light and quick — a small card,
  not a full window.
- **Controls row (Feed):** the company filter and sort toggle are quiet — hairline borders,
  secondary text, accent only on the active state.

## Tone

- Restraint over decoration. One accent color, used sparingly.
- Whitespace is calm but the lists are dense — the contrast (airy chrome, tight rows) is the
  Claude-meets-Postman feel.
- Motion: subtle. Fades and small scale on the overlay appear; no bouncy animation.

## Acceptance criteria

- [ ] Headings render in a serif (New York); body/UI in SF Pro.
- [ ] Palette matches the tokens above; the only accent is Claude orange.
- [ ] Feed rows are compact with clear title / metadata hierarchy and a subtle hover.
- [ ] The `+` button is a floating orange circle, bottom-right.
- [ ] Modal and overlay use the warm surface, serif title, and tiny-font fields.
