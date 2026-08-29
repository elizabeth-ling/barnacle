# Barnacle — Project Overview & Architecture

> **Read this first.** This document holds the decisions every other spec depends on:
> the tech stack, the data model, the scrape strategy, and the answers to the two open
> questions. Specs `01`–`06` describe individual features. Build in numeric order.

---

## 1. What we're building

A **personal macOS app** that tracks internship postings from a hand-picked list of
companies, surfaces them in a fast dashboard sorted by newest, notifies the user when
something new appears, and lets the user log jobs they've applied to — including via a
global `⌘J` overlay that works over any app.

This is a single-user, local-first app. There is no server, no account, no sync. All
data lives on the user's machine.

*(The name fits the behavior: a barnacle picks a few surfaces, clings to them, and quietly
filters the current for what it wants — which is exactly what this app does with your target
companies.)*

### Non-goals (keep it simple)

- No multi-user support, no cloud, no login.
- No general job search / aggregation. Only companies the user explicitly adds.
- No resume tracking, no autofill of applications, no analytics dashboards.
- No non-internship jobs. We filter for internships only.

---

## 2. Two decisions the user asked about

### Q1: Should we also track the LinkedIn careers page, or is it redundant?

**Decision: Skip LinkedIn. Use official careers pages only.**

Reasons:
- For the user's goal — tracking *specific* companies — the official careers page is the
  source of truth. LinkedIn is a mirror of it, so it's mostly redundant.
- LinkedIn actively blocks scraping (auth walls, bot detection, rate limits) and its terms
  prohibit it. It's the single least reliable source we could pick.
- Official careers pages are far more tractable because **most companies run their careers
  page on a known ATS** (Greenhouse, Lever, Ashby, Workday, SmartRecruiters) that exposes a
  clean JSON endpoint (see §4). That gives us structured, reliable data with near-zero parsing.

**Escape hatch:** if the user later finds a company that *only* posts on LinkedIn, that
company can be handled by the "generic" adapter path (§4) or added manually. Don't build
LinkedIn support up front.

### Q2: Native macOS app, or cross-platform desktop app?

**Decision: Native macOS app (SwiftUI).**

The user described the headline feature themselves: a `⌘J` overlay that floats **on top of
everything, including full-screen apps like Chrome**, so they can log an application without
leaving what they're doing. macOS lets a native `NSPanel` sit above full-screen Spaces
cleanly (via window level + `canJoinAllSpaces` + `fullScreenAuxiliary`; see spec `05`).
Electron/Tauri can register a global shortcut, but reliably floating an always-on-top window
*over other apps' full-screen Spaces* is exactly where the web stack fights the OS.

The user also said "it's specifically for me" and values a "seamless experience" — which
removes the only real argument for cross-platform (sharing). So we optimize for seamlessness.

**Honest trade-off to be aware of:** native is *not* the absolute least code. The overlay,
menu-bar presence, and notifications are all cleaner natively, but you'll write Swift. The
genuinely hard part of this project — parsing many different careers pages — is equally hard
in any stack, and §4 makes it much easier by targeting ATS JSON APIs instead of HTML. So the
native choice costs us a little on the shell and buys us the one feature that matters most.

*(If the user ever decides the overlay isn't worth it, the fallback is a Tauri app — but do
not build that now. These specs assume native macOS.)*

---

## 3. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language / UI | **Swift + SwiftUI**, macOS 14 (Sonoma) or newer | Native serif font (New York) and system fonts fit the UI spec for free. |
| App shape | **Menu-bar extra + main window** | Menu-bar item keeps the app alive to scrape and listen for `⌘J`. Main window has the two tabs. Optional "launch at login." |
| Storage | **SwiftData** (or GRDB/SQLite if the agent prefers) | Data model is tiny. SwiftData minimizes boilerplate. GRDB is a fine, more battle-tested alternative — pick one and note it in code. |
| Networking | `URLSession` | For ATS JSON APIs. |
| HTML fallback parsing | **SwiftSoup** (SPM) | Only for the "generic" adapter. |
| Global hotkey | **HotKey** package (soffes/HotKey, wraps Carbon) | Reliable global `⌘J` even when unfocused. |
| Notifications | `UserNotifications` (native) | Default. Free, zero-setup. |
| Phone push (optional) | **ntfy** via `URLSession` (one HTTP POST) | Off by default; reaches the user's iPhone. Twilio SMS is an alternative; iMessage is avoided. See spec `04`. |

Dependencies are intentionally few: `HotKey` and `SwiftSoup`. Everything else — including the
optional ntfy phone push, which is just an HTTP POST — uses first-party Apple frameworks.

---

## 4. Scraping strategy — ATS adapters (the core idea)

Do **not** write a bespoke HTML scraper per company. Instead, detect which Applicant
Tracking System (ATS) a careers URL uses, and call that ATS's public JSON endpoint. This is
the single most important simplification in the whole project.

When the user adds a company URL, run **adapter detection** (spec `03`) to classify it:

| ATS | Detect by URL contains | JSON endpoint pattern |
|---|---|---|
| **Greenhouse** | `boards.greenhouse.io/{token}` or `greenhouse.io` | `https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true` |
| **Lever** | `jobs.lever.co/{token}` | `https://api.lever.co/v0/postings/{token}?mode=json` |
| **Ashby** | `jobs.ashbyhq.com/{token}` | Ashby posting API (JSON); resolve `{token}` from URL. |
| **SmartRecruiters** | `smartrecruiters.com/{token}` | `https://api.smartrecruiters.com/v1/companies/{token}/postings` |
| **Workday** | `myworkdayjobs.com` | Workday CXS JSON POST endpoint (more involved; implement last). |
| **Generic** | anything else | Fetch HTML, parse with SwiftSoup + heuristics; optional LLM fallback (below). |

Each adapter implements one protocol:

```swift
protocol ATSAdapter {
    static func matches(url: URL) -> Bool
    func fetchInternships(for company: Company) async throws -> [JobPosting]
}
```

`fetchInternships` returns only postings whose title matches the internship filter (§6).
Build adapters in this order: **Greenhouse → Lever → Ashby → SmartRecruiters → Generic →
Workday**. Greenhouse + Lever alone cover a large share of tech internships, so the app is
useful after just those two.

**Optional LLM fallback for the generic adapter:** if HTML heuristics fail, the raw page
text can be sent to the Claude API (recommend **Claude Haiku 4.5** — cheap and fast) with a
prompt asking it to return a JSON array of `{title, url, datePosted}` for internship roles.
This is *optional* and off by default; it requires an API key in Settings. Don't block the
project on it.

---

## 5. Data model

Three entities. Keep them this small.

### Company
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | Display name the user typed. |
| `careerURLs` | [String] | One or more. Usually one. |
| `atsType` | enum | `greenhouse, lever, ashby, smartRecruiters, workday, generic` — set by detection. |
| `atsToken` | String? | The board token parsed from the URL (e.g. Greenhouse `{token}`). |
| `isActive` | Bool | If false, skip during scrape. Default true. |
| `dateAdded` | Date | |

### JobPosting
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Our internal id. |
| `companyID` | UUID | FK → Company. |
| `companyName` | String | Denormalized for fast list rendering. |
| `title` | String | |
| `url` | String | Direct link to the posting. Opens in browser on click. |
| `datePosted` | Date? | From the ATS when available (Greenhouse `updated_at`, Lever `createdAt`, etc.). |
| `dateFirstSeen` | Date | When our scraper first saw it. Used for sort/date when `datePosted` is nil. |
| `location` | String? | Optional; show if present. |
| `rawID` | String | The ATS's own job id. Primary key for dedup. |

**Effective date** (used everywhere for display + sort) = `datePosted ?? dateFirstSeen`.

**Dedup / "is new":** a scraped posting is *new* if no stored `JobPosting` exists with the
same `(companyID, rawID)`. New postings are inserted and flagged to the notifier (spec `04`).
Postings that disappear from the source may be marked closed/removed, but **don't delete
them** — the user may still want the record. (Keep a `closedAt: Date?` if easy; optional.)

### Application (jobs the user applied to — the second tab)
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `companyName` | String | Typed by user (may not match a tracked Company). |
| `jobTitle` | String | |
| `url` | String? | Optional. |
| `dateApplied` | Date | Defaults to now on creation. |
| `status` | enum | `applied, interviewing, offer, rejected, ghosted`. Default `applied`. |
| `notes` | String? | Optional freeform. |

Applications are **fully manual** and independent of scraped postings (no FK required). If
the user opens the overlay while viewing a posting, we can pre-fill fields (nice-to-have),
but the entity stands alone.

---

## 6. Internship filter

A posting counts as an internship if its **title**, lowercased, contains any of these as a
**whole word** (with an optional plural `s`): `intern`, `internship`, `co-op`, `co op`, `coop`.

Include the co-op variants because some companies use that term. This runs inside each adapter
so we never store non-internship jobs.

**Match whole words, not substrings.** A plain `contains "intern"` check reads *"Internal Audit
Lead"* as an internship — on Stripe's live Greenhouse board that was 9 false positives out of 11
matches, all of which would have reached the feed and fired notifications. Word boundaries drop
those while still catching "Intern", "Interns", "Internship", and the co-op spellings. The
optional trailing `s` is what catches plurals, since `intern` as a whole word does not match
"Interns" on its own. `internship` earns its own entry under this rule: whole-word `intern` no
longer covers it, the way a substring check did.

Implemented in `InternshipFilter` (`Barnacle/Models/InternshipFilter.swift`) as a per-keyword
regex, `\b<keyword>s?\b`, against the lowercased title. Keep the keyword list as the source of
truth — the matching rule is applied to every entry in it.

---

## 7. Scrape schedule

- **Interval: every 15 minutes**, with ±2 min random jitter to avoid hammering all sources
  on the exact same tick.
- Rationale: internship applications are time-sensitive (early applicants have an edge), so
  we want to be responsive — but ATS JSON endpoints are cheap, so 15 min is plenty fast
  without being abusive. This sits in the middle of the user's requested 10–30 min window.
- Scrape only `isActive` companies. Iterate sequentially with a short delay (~1–2s) between
  companies to be polite.
- Also scrape once on app launch, and expose a manual **"Refresh now"** action.
- Store `lastScrapedAt` per company for display and debugging.

---

## 8. App structure (two tabs + overlay)

1. **Feed tab** (spec `02`) — the main dashboard: internships sorted newest-first, filter by
   company, sort toggle, click-to-open, the `+` button to add a company (spec `03`).
2. **Applied tab** (spec `05`) — manually tracked applications; add via the in-window button
   or the global `⌘J` overlay.
3. **Global `⌘J` overlay** (spec `05`) — floats over everything, including full-screen apps.
4. **Menu-bar extra** — shows unread-new count, quick "Refresh now," "Open Barnacle,"
   quit. Keeps the app alive in the background.
5. **Settings** — scrape interval (optional to expose), notification prefs, optional iPhone
   push (ntfy topic; Twilio as alternative), + optional Claude API key.

---

## 9. Suggested build order

1. Data model + storage (§5).
2. Greenhouse adapter + scrape loop (spec `01`), verified against one real company.
3. Feed tab UI (spec `02`) + design system (spec `06`).
4. Add-company modal + adapter detection (spec `03`).
5. Notifications, native first (spec `04`).
6. Applied tab + `⌘J` overlay (spec `05`).
7. Lever / Ashby / SmartRecruiters / Generic adapters.
8. Optional: Twilio SMS, Workday adapter, LLM fallback.

Each spec lists concrete acceptance criteria. Ship after step 5 is fully working; the rest
is breadth and polish.
