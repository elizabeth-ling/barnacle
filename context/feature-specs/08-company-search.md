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

## Acceptance criteria

- [ ] Typing "Stripe" in the Add-Company modal finds its Greenhouse board without a URL.
- [ ] "Ramp" and "Notion" resolve to Ashby; "Scale AI" slugifies to `scaleai` and resolves.
- [ ] A name matching several boards lists all of them with role counts and requires a choice.
- [ ] A name matching nothing falls through to the URL field with a clear message.
- [ ] Role counts reflect the user's spec-`07` settings, not the board's total.
- [ ] Probing is parallel and uses the short detection timeout; the modal never hangs.
- [ ] The chosen result flows through the existing `CompanyURLChecker` outcomes.
- [ ] `ManageCompaniesView` can edit a company's URL and re-run detection.
- [ ] `xcodebuild -scheme Barnacle -configuration Debug build` succeeds with no new warnings.
