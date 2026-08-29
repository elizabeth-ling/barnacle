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

- **Status** is an inline dropdown: `Applied, Interviewing, Offer, Rejected, Ghosted`.
- Clicking a row (or a disclosure) reveals `url` (opens in browser) and `notes`.
- An in-window **"+ Add application"** button opens the same entry form the overlay uses.
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
- [ ] Applications list newest-first with company, role, applied date, and status.
- [ ] Status can be changed inline; url opens in browser; notes are editable.
- [ ] "+ Add application" creates a record via the shared form.
- [ ] Tab is fully usable offline.

**Overlay**
- [ ] `⌘J` opens the overlay while a *different* app is focused.
- [ ] `⌘J` opens the overlay while another app is **full-screen** (verify with full-screen
      Chrome specifically — the panel floats above it, no Space switch).
- [ ] Overlay is focused for immediate typing without fully activating Barnacle.
- [ ] `Return` saves and closes; `Esc` closes without saving; focus returns to prior app.
- [ ] A saved overlay entry appears in the Applied tab right away.
- [ ] Works whether or not the main window is open, because the app runs in the menu bar.
