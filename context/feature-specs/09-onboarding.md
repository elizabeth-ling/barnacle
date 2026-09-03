# Spec 09 — First-Run Onboarding

Depends on: `07` (the preferences it sets), `08` (the company search in step 3), `06`.
**Build last.** Onboarding is a shell over `07` and `08`; building it first means building a
wizard for settings that do not exist yet.

## Purpose

A first launch currently opens an empty Feed with a `+` and no explanation. Three steps fix that,
and they are the same three decisions the app actually depends on: what role, which countries,
which companies.

## The rule that keeps this cheap

**Onboarding owns no state.** Each step writes straight into the same `ScrapePreferences` object
`SettingsView` edits, and step 3 uses the same add-company path as the `+` button. The steps are
existing controls in a different container.

If onboarding ever needs its own model, something has been duplicated — go find it.

## Flow

A sheet over the main window, not a separate window: `RootView` presents it when
`onboarding.completed` is absent from `UserDefaults`. One `Window` scene stays the shape of the
app (`§8`).

Chrome per `06`: surface card, serif step title, `barnaclePrimary` for the forward action,
`barnacleSecondary` for **Skip**. A three-dot step indicator, no progress bar — three steps do not
need a percentage.

### Step 1 — Role level

"What are you looking for?" Two large options, **Internships** and **New grad**, one selected by
default (`.internship`). Continue is always enabled.

One line beneath: "You can change this in Settings when you graduate." That sentence is doing real
work — it tells the user this is a durable setting rather than a filter, which is the whole design
premise.

### Step 2 — Countries

"Where would you work?" United States and Canada pinned and pre-checked; a search field for the
rest. The unknown-location switch from `07` sits at the bottom, on, with its one-line explanation.

At least one country must be selected before Continue enables — zero countries means an app that
can never show anything, which is not a state worth supporting.

### Step 3 — Add companies

"Which companies are you tracking?" The spec-`08` search field, with each added company appearing
in a list beneath it. Role counts come from the settings just chosen in steps 1 and 2, so the user
sees the consequence of their own answers immediately — the best possible confirmation that the
first two steps did something.

**Done** is enabled with zero companies. A user who wants to explore first should not be trapped in
a wizard. The Feed's existing "no companies" empty state already handles that landing.

## Completion

- Set `onboarding.completed`, dismiss, and kick off the first scrape immediately — the payoff for
  step 3 is postings appearing.
- **Skip** at any step sets the same flag and keeps the defaults (`.internship`, US + Canada,
  unknown locations included). A skipped onboarding leaves a working app, never a half-configured
  one.
- Settings gains **Show onboarding again**, which clears the flag and re-presents. Cheap, and the
  only way to see this flow twice without deleting the container.

## Acceptance criteria

- [ ] First launch presents onboarding; a second launch does not.
- [x] Each step writes into `ScrapePreferences`; onboarding holds no model of its own.
- [ ] Step 2 requires at least one country; step 3 does not require a company.
- [ ] Skip at any step completes with working defaults.
- [ ] Step 3's role counts reflect the choices made in steps 1 and 2.
- [ ] Completing runs a scrape immediately.
- [ ] "Show onboarding again" in Settings re-presents the flow.
- [x] `xcodebuild -scheme Barnacle -configuration Debug build` succeeds with no new warnings.
