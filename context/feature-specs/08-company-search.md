# Spec 08 — Add a Company by Name

Depends on: `03` (the Add-Company modal, `ATSDetector`, `CompanyURLChecker`), `06`.

## Purpose

Let the user type **"Stripe"** instead of hunting down
`https://boards.greenhouse.io/stripe`. Today adding a company means finding its careers URL by
hand, which is the single most tedious thing in the app and the reason a wrong URL sits in the
store until someone notices it scrapes nothing.

## There is no company directory to search

Greenhouse, Lever, and Ashby publish **no company search endpoint**. There is no list to query.
So this is not really search — it is **probing**, and probing works because ATS board tokens are
almost always the company name lowercased and de-spaced.

Measured against live endpoints, slugified name → board:

```
stripe     greenhouse 200      figma       greenhouse 200
ramp       ashby      200      notion      ashby      200
anthropic  greenhouse 200      databricks  greenhouse 200
scaleai    greenhouse 200      vercel      greenhouse 200 + ashby 200
```

Eight of eight resolved. This is the whole mechanism.

## How it works

1. **Slugify** the typed name: lowercase, strip diacritics, drop everything but `a–z0–9`.
   `"Scale AI"` → `scaleai`, `"Match Group"` → `matchgroup`. Also generate a hyphenated variant
   (`scale-ai`) — some boards use it — and try both.
2. **Probe in parallel** across the adapters that have a token-shaped URL and a working adapter:
   - Greenhouse — `https://boards-api.greenhouse.io/v1/boards/{slug}/jobs`
   - Lever — `https://api.lever.co/v0/postings/{slug}?mode=json`
   - Ashby — `https://api.ashbyhq.com/posting-api/job-board/{slug}`

   Parallel, not sequential: this blocks a modal, so it wants the shorter timeout
   `PageFetch` already uses for detection, not the scrape timeout.
3. **Collect the hits.** Each is a real candidate with a real token.
4. **Count matching roles** per hit by running the posting list through the same
   `RoleLevelFilter` + `LocationClassifier` the scraper uses (spec `07`), so the count shown is
   the count the user would actually receive — not the board's total headcount.

## Presenting results

- **No hits** → fall through to the existing URL field, unchanged. Message: "Couldn't find a job
  board for that name. Paste the careers URL instead." Typing a name must never become a
  dead end.
- **One hit** → show it as a single selectable row with its ATS and role count, pre-selected.
  `Return` adds it.
- **Several hits** → list them all and make the user choose. `vercel` genuinely answers on both
  Greenhouse and Ashby, so guessing would be wrong roughly as often as it is right. The role
  count is the disambiguator: a stale board usually reports zero.

Each row shows company name, ATS, and "N matching roles" — reusing `CompactRow` from `06` so this
looks like the rest of the app.

## Reuse, don't rebuild

The probe produces a URL. Hand that URL to the **existing** `CompanyURLChecker.check(_:companyName:)`
and let its four outcomes (`invalid` / `reachable` / `noAdapterYet` / `unreachable`) drive the
modal exactly as they do today. This spec adds a way to *discover* a URL; it does not add a second
validation path.

## Fixing a wrong URL

Spec `04` recorded that `ManageCompaniesView` can pause or remove a company but not edit its URL,
so a wrong URL means remove and re-add — which is how Notion and Ramp ended up saved against
404ing Greenhouse and Lever URLs.

Add **Edit URL** to `ManageCompaniesView`: the same field and the same checker, re-running
detection on save. With the probe in place, the natural repair for a bad URL is to re-probe the
name.

## As built

Three decisions worth recording, all consistent with the spec rather than departures from it:

- **One row per ATS.** Both slug variants can answer on the same board (`scaleai` *and*
  `scale-ai`), and offering the same company twice under the same ATS is a choice with no
  meaning. `CompanyProbe` keeps the richer hit per ATS, breaking ties towards the first slug
  tried, and sorts the survivors by role count.
- **The short timeout is a deadline around the adapter, not a request timeout.** The probe reuses
  the real adapters so the count comes from the same mapping the scraper uses, and an adapter
  fixes its own request at the scrape budget. `withDeadline` caps the whole parallel probe at 15s
  — the same budget detection already gives a blocking modal — and cancels what's left.
- **Selecting a board fills the URL field.** That is what makes "the chosen result flows through
  the existing `CompanyURLChecker`" literally true: after a pick, Add is the same code path as a
  pasted URL, and the user can see and edit exactly what's about to be saved.

**Edit URL reuses the Add-Company modal** (`AddCompanyView(company:)`) rather than growing a
second form: same fields, same checker, same detection, and the name probe comes along for free —
which is the spec's own suggested repair for a bad URL.

**Re-measured 2026-11-07:** the eight names above still resolve, but `ramp` now also answers on
Greenhouse, with one posting titled "Copy of Chief Legal Officer". So "Ramp" lists two rows, Ashby
first (5 matching roles against 0), and asks for a pick. That is the several-hits rule working as
written, and exactly the stale board the role count is there to expose.

## Acceptance criteria

Checked boxes were confirmed on 2026-11-07 by a standalone harness that compiles the real sources
and drives `AddCompanyModel` and `CompanyProbe` against the live endpoints, with an in-memory store
and a stubbed `URLProtocol` for the timing cases. **That exercises the modal's state machine, not
the rendered sheet.** Nothing here has been seen on screen; the notes say what a person still has
to look at.

- [x] Typing "Stripe" in the Add-Company modal finds its Greenhouse board without a URL.
      *(`greenhouse/stripe`, pre-selected, URL filled, checker passes. Rendered row not seen.)*
- [ ] "Ramp" and "Notion" resolve to Ashby; "Scale AI" slugifies to `scaleai` and resolves.
      *(Notion → Ashby and `Scale AI` → `greenhouse/scaleai` both resolve outright. Left open for
      Ramp: Ashby is found and listed first, but Greenhouse answers too, so it takes a pick rather
      than resolving by itself. See "Re-measured" above.)*
- [x] A name matching several boards lists all of them with role counts and requires a choice.
      *(Vercel: Greenhouse 1, Ashby 0, nothing pre-selected, no URL guessed, nothing savable until
      a pick. Rendered list not seen.)*
- [x] A name matching nothing falls through to the URL field with a clear message.
      *(Exact message, a pasted URL then checks and saves. The cursor moving to the URL field lives
      in the view and has not been seen.)*
- [x] Role counts reflect the user's spec-`07` settings, not the board's total.
      *(Stripe: board total 765, internship 16, new grad 7, Japan-only 0.)*
- [x] Probing is parallel and uses the short detection timeout; the modal never hangs.
      *(Six requests in flight at once, 1.02s against 1s responses. A board that never answers:
      returns at the 15s deadline (15.79s measured) with every request cancelled, and the fields
      stay editable meanwhile. Slowest live probe 0.52s. The check after a pick is spec `03`'s and still runs on
      the adapter's 30s request timeout, with Cancel available.)*
- [x] The chosen result flows through the existing `CompanyURLChecker` outcomes.
- [ ] `ManageCompaniesView` can edit a company's URL and re-run detection.
      *(The model half is confirmed against an in-memory store: load, re-check, paste or re-probe,
      write back onto the same row with the new ATS and token. Left open because the pencil and the
      sheet over `ManageCompaniesView` have never been opened.)*
- [x] `xcodebuild -scheme Barnacle -configuration Debug build` succeeds with no new warnings.
