# Spec 01 — Scraping Engine

Depends on: `project-overview` (§4 adapters, §5 model, §6 filter, §7 schedule).

## Purpose

Fetch internship postings from each active company's careers source on a schedule, dedup
against what we've already stored, and hand any brand-new postings to the notifier (spec `04`).

## Components

### 1. `ATSAdapter` protocol

```swift
protocol ATSAdapter {
    static func matches(url: URL) -> Bool
    func fetchInternships(for company: Company) async throws -> [ScrapedJob]
}

struct ScrapedJob {
    let rawID: String        // ATS's own job id — required, used for dedup
    let title: String
    let url: String
    let datePosted: Date?    // nil if the ATS doesn't expose it
    let location: String?
}
```

Each adapter is responsible for applying the internship title filter (spec `00` §6) before
returning. Adapters never touch storage — they only return data.

### 2. Adapter implementations

Build in this order. First two make the app useful.

**Greenhouse**
- Endpoint: `https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true`
- `{token}` is parsed at company-add time (spec `03`).
- Map: `id → rawID`, `title → title`, `absolute_url → url`, `updated_at → datePosted`,
  `location.name → location`.

**Lever**
- Endpoint: `https://api.lever.co/v0/postings/{token}?mode=json`
- Map: `id → rawID`, `text → title`, `hostedUrl → url`,
  `createdAt` (epoch ms) `→ datePosted`, `categories.location → location`.

**Ashby**
- Endpoint: `https://api.ashbyhq.com/posting-api/job-board/{token}`
- `{token}` is the board name in `jobs.ashbyhq.com/{token}`, parsed at company-add time (spec `03`).
- Map: `id` (UUID string) `→ rawID`, `title → title`, `jobUrl → url` (falling back to `applyUrl`),
  `publishedAt → datePosted`, `location → location`.
- Jobs also carry `isListed`; we deliberately don't filter on it (an unlisted posting is still a
  real opening with a working URL).

**SmartRecruiters**
- Endpoint: `https://api.smartrecruiters.com/v1/companies/{token}/postings`
- Map id, name, `ref`/apply URL, `releasedDate`, location analogously. Paginate if needed.

**Workday** (implement last — more involved)
- Uses a POST to the CXS JSON endpoint derived from the `*.myworkdayjobs.com` host. Requires
  a request body with paging + optional search text ("intern"). Only build once the easier
  adapters are done.

**Generic** (fallback)
- Fetch HTML with `URLSession`, parse with SwiftSoup.
- Heuristic: collect anchor tags whose visible text matches the internship filter; use the
  anchor text as `title`, resolved `href` as `url`, `href` as `rawID` (stable enough).
- `datePosted` usually unavailable → leave nil (effective date falls back to `dateFirstSeen`).
- Optional LLM fallback (spec `00` §4) if heuristics return nothing and an API key is set.

### 3. `ScrapeCoordinator`

Runs the loop:

```
on launch → scrapeAll()
Timer every 15 min ± jitter → scrapeAll()
manual "Refresh now" → scrapeAll()

scrapeAll():
  for each company where isActive:
     pick adapter by company.atsType
     try scraped = adapter.fetchInternships(for: company)
     diff against stored postings (dedup by (companyID, rawID))
     insert new postings (set companyName, dateFirstSeen = now)
     collect new postings → NotificationService.notify(newPostings)  // spec 04
     set company.lastScrapedAt = now
     on error: log, keep going; do not abort the whole run
     sleep ~1–2s between companies
```

- Run off the main thread; publish results so SwiftUI updates the Feed reactively.
- Network failures for one company must not stop the others.
- Coalesce all new postings from one run into a single notification batch (spec `04`).

## Acceptance criteria

- [ ] Adding a real Greenhouse company and refreshing populates the Feed with only
      internship-titled postings, newest first.
- [ ] Re-running a scrape produces **zero** new postings (dedup works; no duplicate notifs).
- [ ] A genuinely new posting appearing at the source is detected on the next scrape and
      handed to the notifier exactly once.
- [ ] One company's network error is logged but doesn't block others in the same run.
- [ ] Lever works with the same guarantees as Greenhouse.
- [ ] `datePosted` is shown when the ATS provides it; otherwise `dateFirstSeen` is used.
