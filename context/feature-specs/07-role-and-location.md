# Spec 07 — Role Level & Location Preferences

Depends on: `01` (scrape pipeline), `04` (notification seam), `06` (design system).
Changes: `§5` data model, `§6` internship filter.

## Purpose

Let the user say, once, **what kind of role** and **which countries** they care about — and never
see anything else. These are settings, not filters: an internship-seeker becomes a new-grad
seeker exactly once, at graduation, and nobody is open to relocating to a new continent between
Tuesday and Thursday.

A filter control the user never touches is noise. There is deliberately **no filter chip, no
toggle, and no "N hidden" counter in the Feed.** Settings is the only surface.

## Where the filter runs

Today each adapter calls `InternshipFilter` before returning, so the filter has four call sites
(`GreenhouseAdapter`, `LeverAdapter`, `AshbyAdapter`, `GenericAdapter`).

**Move it to `ScrapeRunner`.** Adapters return everything the source lists; the runner applies
role level and location before insert.

Two reasons:

1. **Reconciliation stays honest.** `ScrapeRunner.reconcileClosed` compares stored postings
   against the set that survived the filter. With filtering inside the adapter it cannot tell
   "gone from the source" from "no longer matches your settings."
2. **One home.** The rule lives in one place instead of four, and a new adapter gets it for free
   rather than having to remember.

Filtering stays at **scrape time**, not read time: nothing unwanted is ever stored, so every
consumer — Feed, notifications, menu-bar count, anything added later — is correct by construction
and cannot leak a Bengaluru posting through a forgotten predicate. This preserves the invariant
already documented on `JobPosting`: *only postings that pass the filter are ever stored*.

## Preferences

`ScrapePreferences` — a `@MainActor @Observable` class over `UserDefaults`, modeled exactly on
`NotificationPreferences`. Not `@AppStorage`: `ScrapeRunner` reads these outside any view, and it
and `SettingsView` must see the same values, so a change takes effect on the next scrape with no
restart.

| Key | Type | Default |
|---|---|---|
| `scrape.roleLevel` | `RoleLevel` | `.internship` |
| `scrape.countries` | `Set<String>` (ISO 3166-1 alpha-2) | `["US", "CA"]` |
| `scrape.includeUnknownLocation` | `Bool` | `true` |

Read defaults with `object(forKey:)`, never `bool(forKey:)` — an unset key must not read as
`false` and silently strangle a fresh install.

## Role level

`RoleLevel` is an enum, not a pair of bools — the two are mutually exclusive in practice and an
enum makes "neither selected" unrepresentable.

```swift
enum RoleLevel: String, CaseIterable { case internship, newGrad }
```

`RoleLevelFilter` replaces `InternshipFilter` and keeps its whole-word rule (`\b<keyword>s?\b`
against the lowercased title, per `§6`) — the rule that stopped "Internal Audit Lead" reading as
an internship.

- **`.internship`** — the existing keywords: `intern`, `internship`, `co-op`, `co op`, `coop`.
- **`.newGrad`** — `new grad`, `new graduate`, `university grad`, `university graduate`,
  `entry level`, `entry-level`, `early career`, `campus`, `graduate`.

`graduate` alone repeats `§6`'s exact trap: it matches "Graduate Program Manager" and "Graduate
Recruiter." So `.newGrad` also carries a **negative list** applied after the keyword match —
`program manager`, `recruiter`, `recruiting`, `coordinator`, `director`, `manager`, `lead`,
`senior`, `staff`, `principal`. A title matching a negative term is rejected however well it
matched.

Keep both keyword lists as the source of truth; the matching rule applies to every entry.

## Location

Country-level only. Not states, not cities, not regions — the user asked for country granularity
and a region tree is a schema you cannot walk back cheaply.

### The data is free text and it is messy

Sampled from live boards:

| Source | Real values |
|---|---|
| Greenhouse (Databricks) | `San Francisco, California`, `Bengaluru, India`, `United States`, `Mountain View, California; San Francisco, California` |
| Greenhouse (Stripe) | `Dublin`, `US`, `US-Remote`, `Toronto`, `N/A` |
| Lever | `New York, New York`, plus a separate `workplaceType` |
| Ashby | `location` **and** structured `address.postalAddress.addressCountry`, `secondaryLocations`, `isRemote` |

Ashby is the only ATS that states the country outright. `AshbyAdapter` currently decodes only
`location` and throws the rest away — decode `address`, `secondaryLocations`, and `isRemote`, and
prefer the structured country over any text guess.

### `LocationClassifier`

Input: the raw location string (plus structured country when the adapter has one).
Output: `(countryCode: String?, isRemote: Bool)`, where `nil` means **unknown**, not "nowhere."

Resolution order, first hit wins:

1. **Structured country** from the ATS (Ashby). Authoritative.
2. **Explicit country** token — full names and codes: `United States`, `USA`, `US`, `Canada`,
   `India`, `United Kingdom`, `UK`, `Ireland`, …
3. **US state** name or postal abbreviation → `US`. **Canadian province** name or abbreviation
   → `CA`. This is what resolves `San Francisco, California` and `Toronto, Ontario`.
4. **City gazetteer** — a small curated table of unambiguous major hubs (`Bengaluru`, `Hyderabad`,
   `Singapore`, `Tokyo`, `Amsterdam`, `Seoul`, `Sydney`, …). Deliberately excludes ambiguous
   names: **`Dublin` is not in the table** (Ireland vs. Dublin, California) and neither is
   `London` (UK vs. Ontario). They resolve to unknown, which is the honest answer.
5. Otherwise **unknown**.

`Remote` anywhere in the string sets `isRemote`. `US-Remote` yields `("US", true)`.

**Multi-location strings** split on `;`, `/`, `|`, and ` and `. Each part is classified
separately and the posting carries the full set.

### The rejection rule — reject only on a confident non-match

A posting is dropped **only if every part classified confidently and none is in the allowed
set.** If any part is unknown, the posting is kept.

This asymmetry is the whole point. Role level matches on the title — high signal, and a mistake is
visible. Location is free text with genuine ambiguity, and at scrape time a misclassification
isn't a filter you can flip off: the posting is never stored and never seen. A San Francisco
internship silently missed because the ATS wrote something unusual is the one failure that costs
a job. So `Bengaluru, India` and `London, United Kingdom` never get stored, while `N/A` and
`Dublin` do — and the row shows the raw string so the user can judge it themselves.

`includeUnknownLocation` exposes this as a switch for a user who would rather have the quiet feed.

**An empty country set means no country restriction**, not "nothing anywhere" — the picker can be
emptied, and a feed that could never fill again would be a baffling result for one stray click.

**Ambiguity is resolved towards the US, deliberately.** Two collisions matter in practice and the
spec's resolution order gets both wrong: `Atlanta, Georgia` is not Tbilisi, and `San Francisco, CA`
is not Canada. So a country *name* that is also a US place (`Georgia`, `Lebanon`) is not read as a
country, and inside a multi-token part a two-letter token is read as a state or province before a
country code. A lone two-letter token keeps the country reading, which is what makes Stripe's bare
`US` work. Every one of these tie-breaks fails towards *keeping* a posting, which is the same
asymmetry the rejection rule is built on.

## Data model changes

Add to `JobPosting`, both optional so they migrate in place:

| Field | Type | Notes |
|---|---|---|
| `countryCode` | `String?` | Set at insert by `LocationClassifier`. Nil = unknown. |
| `isRemote` | `Bool` | Defaults false. |
| `roleLevel` | `String?` | The `RoleLevel` that admitted this posting. |

**Backfill:** existing rows have a `location` string but no `countryCode`. Run the classifier
over stored postings once at launch, guarded by a `scrape.didBackfillRegions` flag.

## Purging on a settings change

When `roleLevel` changes, **delete** the postings that no longer match.

`§5` says "don't delete them — the user may still want the record," but that rationale does not
survive the user's own framing: a posting is worth applying to for about two days, so a closed
internship listing after graduation is worth nothing. Recorded here as a deliberate deviation,
like `§6`'s whole-word rule.

Deleting rather than hiding also makes the transition clean with no special-casing. Internships
are purged, new-grad postings arrive as genuinely new, and there is no wall of stale NEW badges
and no notification flood to suppress. **Note that hiding would not work today anyway:** nothing
in the app reads `closedAt` — `ScrapeRunner` writes it and no view consumes it, so a "closed"
posting currently renders exactly like a live one.

A country change purges the same way for postings that now classify outside the allowed set.
Unknown-location postings are never purged.

Trigger a refresh immediately after any purge so the feed refills in the same beat.

**Confirm before purging.** The dialog states the count: "Switching to new grad will remove 47
internship postings." This is the one destructive action in the app.

### Why deleting is safe here, and where it is not

Deleting normally fights the scrape loop: dedup is `(companyID, rawID)`, so a deleted posting that
is still listed at the source gets re-inserted on the next run and notified about a second time.
This is why spec `02`'s dismissal marks `dismissedAt` instead of deleting.

A settings purge escapes that trap for one specific reason: **the purge criterion and the new
filter criterion are the same.** Postings deleted for no longer matching cannot come back, because
the runner now rejects them on the way in. Delete only ever when those two agree.

## Optional — age-out

Drop postings whose `effectiveDate` is older than N days (default 30, or off). By the two-day
logic a three-week-old posting is noise regardless of graduation.

**This one must not delete.** An age-out criterion is *time*, not the scrape filter, so a 30-day-old
posting that is still live on the board would be deleted and then re-inserted as new on the very
next run — a resurrection plus a spurious notification. Age-out has to hide, using the same
`dismissedAt`-style tombstone spec `02` uses, or a dedicated `agedOutAt`.

Off by default; ship `07` without it if it adds risk.

**Not built.** `07` shipped without age-out, on the permission above: it needs a fourth stored
field and a second, differently-shaped hiding rule, and neither earns its risk next to the
filter move and the purge. `dismissedAt` already lets the user clear a stale posting by hand.

## Settings UI

A new section above Notifications in `SettingsView`, built from `06`'s tokens — section title in
serif, `Theme.Metrics.fieldSpacing`, existing button styles.

- **Role level** — a two-option segmented control ("Internships" / "New grad").
- **Countries** — a compact multi-select. United States and Canada pinned to the top as the
  common case; the rest behind a search field. Not a 200-row scroll.
- **Include postings with an unrecognized location** — a switch, on by default, with the
  one-line explanation that some boards don't state a country.

## Notifications

`NotificationService` needs no change if the filter is at scrape time — a posting that reaches
the store already matches. That is the argument for scrape-time filtering in one sentence: the
notification path cannot get this wrong, because it never sees the postings.

## Empty state

The Feed's existing `EmptyState` gains a variant for "your settings matched nothing": when the
store is empty but companies exist and a scrape has completed, say whether the settings are the
reason and offer a button to open them. This replaces the "N hidden" counter — the information
appears exactly when it is useful and never as permanent chrome.

## Acceptance criteria

- [ ] Role level and countries are set in Settings; neither appears as a Feed control.
- [x] `RoleLevelFilter` matches whole words; "Internal Audit Lead" and "Graduate Program Manager"
      are both rejected.
- [x] The filter runs in `ScrapeRunner`; no adapter calls it.
- [x] `reconcileClosed` no longer marks a posting closed merely because settings changed.
- [ ] A posting in `Bengaluru, India` is never stored with the default settings.
- [ ] A posting in `N/A` or `Dublin` **is** stored, and its raw location shows in the row.
- [ ] `San Francisco, California`, `Toronto`, `US-Remote`, and `United States` all classify to an
      allowed country.
- [ ] A multi-location posting is kept if any of its locations is allowed.
- [ ] `AshbyAdapter` decodes structured country and prefers it over the text guess.
- [ ] Switching role level asks for confirmation with a count, purges, and refreshes.
- [ ] Existing postings are backfilled with a country once, at launch.
- [x] `xcodebuild -scheme Barnacle -configuration Debug build` succeeds with no new warnings.
