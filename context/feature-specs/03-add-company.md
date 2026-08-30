# Spec 03 — Add Company (Modal + Adapter Detection)

Depends on: opened from `02` (the `+` button).

## Purpose

Let the user add a company to track by typing its name and one or more careers-page URLs.
On save, detect which ATS the URL uses so the scraper knows which adapter and token to use.

## The modal

Opened by the floating `+` button (bottom-right of the Feed).

Fields:
- **Company name** (text, required).
- **Careers URL(s)** (one required; allow adding more with a small "+ add another URL"
  control). Most companies need only one.

Buttons: **Cancel**, **Add**. `Return` submits, `Esc` cancels.

Styling per spec `06` (warm modal surface, serif title "Add company", tiny-font fields).

## Adapter detection (on Add)

For each URL, run detection to set `atsType` and `atsToken`:

1. Normalize the URL (add scheme if missing, lowercase host).
2. Match against known ATS host patterns (spec `00` §4):
   - `boards.greenhouse.io/{token}` or `job-boards.greenhouse.io/{token}` → **greenhouse**,
     token = first path segment.
   - `jobs.lever.co/{token}` → **lever**, token = first path segment.
   - `jobs.ashbyhq.com/{token}` → **ashby**, token = first path segment.
   - `{token}.smartrecruiters.com` or `careers.smartrecruiters.com/{token}` →
     **smartRecruiters**, token accordingly.
   - `*.myworkdayjobs.com` → **workday** (store enough of the host/path to build the CXS
     endpoint later).
   - anything else → **generic**.
3. If a page embeds a known ATS rather than linking to it directly (common: a company's own
   `/careers` page that iframes or links to Greenhouse), optionally fetch the HTML once and
   look for known ATS URLs/script tags to reclassify. Nice-to-have; the generic adapter is
   the safe fallback if detection is unsure.

**One classification, several URLs.** `Company` (spec `00` §5) holds a single `atsType` /
`atsToken`, so a company adopts its **first** URL's classification. Every URL's detected ATS is
shown in the modal, so a company whose URLs disagree is visible rather than silent. Splitting the
classification per URL would mean a schema change; nothing needed it yet.

### Validation before saving

- After detecting, do a **one-shot test fetch** using the chosen adapter.
  - Success (endpoint reachable, parses) → show a green check and, if easy, a count like
    "Found 3 internships." Save the Company.
  - Failure → keep the modal open with an inline message: "Couldn't read this careers page
    automatically. Save anyway as a generic page?" Let the user save as `generic` or fix the
    URL. Never silently save something that will never scrape.

## Managing companies (lightweight)

Not a full CRUD screen — keep it simple:
- The company filter dropdown (spec `02`) is where tracked companies are visible.
- Provide a way to **remove** a company and to **toggle active/inactive** — e.g. a small
  "Manage companies" list reachable from Settings or a right-click on the filter entry.
  Removing a company should offer to keep or discard its stored postings (default: keep).

## Acceptance criteria

- [x] `+` opens the modal; name + one URL + Add creates a tracked company.
- [x] A Greenhouse/Lever URL is correctly classified with the right token.
- [x] A test fetch runs on Add; success confirms, failure explains and offers "save as
      generic."
- [x] Multiple URLs can be attached to one company.
- [x] The new company appears in the Feed's company filter and is scraped on the next run.
- [x] The user can deactivate or remove a company.
