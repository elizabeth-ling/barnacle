# Spec 05 — Applied Tab + Global ⌘J Overlay

Depends on: `06` (design system).

This spec has two parts: the in-window **Applied** tab, and the **global overlay** that lets
the user log an application from anywhere with `⌘J`. The overlay is the feature that made the
native-macOS choice worth it (spec `00` §2).

---

## Part A — Applied tab

The second tab. A simple, manual list of jobs the user has applied to. No scraping, no
internet required to view it.

### Layout

A table/list of `Application` records, most recent `dateApplied` first:

| Company | Role | Applied | Status |
|---|---|---|---|
| Stripe | SWE Intern | Aug 27 | Applied ▾ |
| Ramp | Design Intern | Aug 24 | Interviewing ▾ |

- **Status** is an inline dropdown: `Applied, Interviewing, Offer, Rejected, Ghosted`. Each
  status carries its own colour (spec `06`), so the list can be scanned by status alone; the
  dropdown and the counts strip both use it.
- Clicking a row (or a disclosure) reveals `url` (opens in browser) and `notes`.
- An in-window **`+`** button opens the same entry form the overlay uses. It sits at the end of
  the header's control row, next to the sort toggle. *(Moved there from a floating bottom-right
  circle on 2026-09-02; see spec `06`.)*
- Allow edit and delete of a row.
- Optional light touch: a small count per status at the top ("12 applied · 3 interviewing").

### Behavior

- Fully local; works offline.
- Sorting default: newest `dateApplied` first. Allow sorting by status as a nice-to-have.

---

## Part B — Global ⌘J overlay

### Requirement

From **any** app — including when another app (e.g. Chrome) is **full-screen** — pressing
`⌘J` pops a small, always-on-top overlay to log an application, without switching Spaces or
leaving what the user is doing. `Return` saves, `Esc` dismisses, focus returns to whatever
they were doing.

### Implementation

**Global hotkey**
- Register `⌘J` globally using the **HotKey** package (wraps Carbon `RegisterEventHotKey`),
  so it fires even when Barnacle is not the active app.
- The app must be running for this to work → this is why Barnacle lives as a **menu-bar
  extra** that stays alive in the background (spec `00` §8).

**The overlay window — the critical part**
- Use an **`NSPanel`** (not a normal window) configured as a non-activating floating panel:
  - `styleMask` includes `.nonactivatingPanel` (so showing it doesn't steal focus from the
    full-screen app underneath — it just floats in front).
  - `level = .floating` or higher (e.g. `.screenSaver`) so it renders above normal windows.
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` — this is
    what lets the panel appear **over another app's full-screen Space**. Without
    `.fullScreenAuxiliary`, it won't show over full-screen apps. Get this exactly right.
  - `hidesOnDeactivate = false`, `isFloatingPanel = true`.
- Center it on the screen with the mouse / key window; give it a subtle shadow and rounded
  corners (design spec `06`).
- On show: make it key so the first text field is focused and typing works immediately, but
  do **not** activate the whole app (keep the underlying full-screen app visually present).
- On `Esc` or clicking outside: hide the panel and return focus to the previous app.

**Permissions**
- Global hotkeys via Carbon generally work without Accessibility permission. If the chosen
  approach needs Accessibility (e.g. an event-tap variant), prompt the user once and link to
  System Settings → Privacy & Security → Accessibility. Prefer the Carbon path to avoid this.

### The overlay form

Minimal, fast, keyboard-first:
- **Company** (text, required) — autocomplete from tracked companies + previously used names.
- **Role / title** (text, required).
- **URL** (optional).
- `dateApplied` defaults to **now** (not shown as an input; editable in the Applied tab later).
- `status` defaults to **Applied**.
- **Nice-to-have:** if the frontmost app is a browser and the URL is easy to read, pre-fill
  Company/URL from it. Do not block on this; manual entry is the baseline.

Saving inserts an `Application` and closes the panel. The Applied tab reflects it immediately.

### The same form in-window

The "+ Add application" button in the Applied tab opens the identical form (as a sheet), so
there's one code path for creating applications.

---

## Acceptance criteria

**Applied tab**
- [x] Applications list newest-first with company, role, applied date, and status.
- [x] Status can be changed inline; url opens in browser; notes are editable.
- [x] The `+` creates a record via the shared form.
- [x] Tab is fully usable offline.

**Overlay**
- [x] `⌘J` opens the overlay while a *different* app is focused.
- [x] `⌘J` opens the overlay while another app is **full-screen** (verify with full-screen
      Chrome specifically — the panel floats above it, no Space switch).
- [x] Overlay is focused for immediate typing without fully activating Barnacle.
- [x] `Return` saves and closes; `Esc` closes without saving; focus returns to prior app.
- [x] A saved overlay entry appears in the Applied tab right away.
- [x] Works whether or not the main window is open, because the app runs in the menu bar.

### Verification status

All boxes were exercised against the running app on 2026-09-02.

The panel was confirmed over a full-screen Chromium browser (Arc) — layer 3, on the browser's
own Space, with Barnacle's main window left behind on its Space and no Space switch — from
three starting states: another app frontmost, that app full-screen, and Barnacle itself
frontmost. `⌘J` also toggles the panel closed, and registers in `BarnacleApp.init()`, so it
works with no window open.

The typing path was the last thing to confirm, and it took a real keystroke to do it: synthetic
events (`CGEvent` posted at the HID or session tap) route to the app underneath in this
environment even while the panel is key and showing a blinking insertion point, so they could
neither confirm nor refute it. Typed by hand, the company field is focused the moment the panel
opens, the autocomplete narrows as you type, `Return` saves and closes, `Esc` closes without
saving, focus returns to the app that had it, and the record is in the Applied tab immediately.
The tab's own list, inline status dropdown, link, notes, edit, delete, and the `+` sheet were
confirmed the same way.

Re-confirmed on 2026-09-02 after the status colours landed: the header `+` opens the sheet, a
record saved from it appears immediately, and the coloured dropdown and counts strip render as
specified. That check is also what caught the dropdown's chrome never rendering at all — see
the note in spec `06`'s components list.

### Deviation: the overlay activates Barnacle, without moving anything

The spec asks for a non-activating panel that is nonetheless focused for typing. On macOS those
two are in tension: a key window only receives keyboard input while its app is *active*, and
`.nonactivatingPanel` alone leaves Barnacle inactive, so the keystrokes go to the app underneath.
Activating a `.regular` app, meanwhile, makes macOS reveal the Space its ordinary windows live
on — the Space switch this feature exists to avoid.

`QuickAddOverlay.show()` resolves it by spending the life of the panel as an **accessory** app:
order the panel front, `NSApp.activate()`, then make the panel key. Accessory apps carry no
obligation to reveal their other windows, so the Space stays put; `hide()` returns focus to the
app that had it and restores `.regular`. The panel keeps `.nonactivatingPanel` (nothing of
Barnacle's is pulled forward) and the collection behavior the spec specifies. When Barnacle is
already the active app the dance is skipped entirely — running it from there makes AppKit tear
the panel back down before it appears.
