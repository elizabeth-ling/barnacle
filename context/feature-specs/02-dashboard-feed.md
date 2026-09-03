# Spec 02 — Dashboard (Feed Tab)

Depends on: `01` (data source), `06` (design system).

## Purpose

The main screen. A dense, fast list of internship postings from tracked companies, newest
first, with filtering by company and a sort toggle. This is the first tab and the default
view on launch.

## Layout

```
┌─────────────────────────────────────────────────────────┐
│  Feed        Applied                         [Refresh ↻] │   ← tab bar + refresh
├─────────────────────────────────────────────────────────┤
│  [ Filter by company ▾ ]   Sort: ● Newest ○ Oldest   ( + ) │   ← controls row
├─────────────────────────────────────────────────────────┤
│  Stripe        Software Engineer Intern      2h ago      │   ← row (clickable)
│  Ramp          Product Design Intern         5h ago      │
│  Notion        ML Research Intern            Yesterday   │
│  …                                                        │
└─────────────────────────────────────────────────────────┘
```

## Row content

Each row shows, per the user's request:
- **Company name** (secondary weight/color)
- **Job title** (primary — the thing you read first)
- **Date & time posted** — use the *effective date* (`datePosted ?? dateFirstSeen`).
  Format relatively for recent items ("2h ago", "Yesterday"), absolute for older
  ("Aug 21"). On hover, show the full timestamp as a tooltip.
- **Location** — `location` when the ATS provides one, as muted trailing text immediately
  before the date. Hidden entirely when the source doesn't supply one, rather than showing
  a placeholder.
- A small **"NEW"** badge (Claude-orange dot or pill) on postings the user hasn't opened
  yet. Clear the flag once the row is clicked.

  *This originally read "first seen in the last 24h **or** not yet viewed," which fights the
  clear-on-click rule: a posting clicked an hour after it arrived is still inside its 24h
  window. Unviewed is the clause that survives — anything first seen in the last 24h is
  unviewed anyway, unless the user already opened it, and then the badge must be gone.
  Implemented as `JobPosting.viewedAt` / `isUnviewed`.*

Keep rows compact and tidy (Postman-like density, tiny fonts — see spec `06`).

## Interactions

- **Click a row → open `url` in the default browser in a new tab** (`NSWorkspace.open`).
  Mark the posting as viewed (clears its NEW badge).
- **Filter by company:** a dropdown/searchable menu listing tracked companies plus "All
  companies." Selecting one filters the list to that company. Should also accept typed text
  to narrow the menu (the user asked to "filter by company name").
- **Sort toggle:** Newest ↔ Oldest by effective date. Default **Newest**. Persist the
  choice across launches.
- **Refresh now:** triggers `ScrapeCoordinator.scrapeAll()` (spec `01`); show a subtle
  spinner while running and the last-updated time when idle.
- **`+` button (end of the controls row):** opens the Add-Company modal (spec `03`).
  *Moved there from a floating bottom-right circle on 2026-09-02; see spec `06`.*

## Dismissing a posting

*Added 2026-09-02 at the user's request.* Postings the user has ruled out — wrong location,
wrong team, already applied — should leave the feed without waiting for the source to close
them.

- **Dismiss:** an `×` at the row's trailing edge, present only while the row is hovered, plus
  a right-click → **Dismiss**. Stored as `JobPosting.dismissedAt`; the posting is *never*
  deleted, because dedup is `(companyID, rawID)` and the next scrape would re-insert it and
  notify about it as if it were new. A dismissal therefore survives re-scrapes, and is
  independent of `closedAt` — a posting reopening at the source must not undo the user's call.
- **Undo:** a banner under the controls row names the posting just dismissed and offers
  **Undo** for six seconds. After that the Dismissed view is the way back.
- **Dismissed view:** a quiet **Dismissed (n)** control sits with the filter and sort controls
  whenever anything is dismissed, and swaps the list for those postings. Each row's trailing
  control becomes a restore arrow (right-click offers **Restore to Feed**). Restoring the last
  one returns the user to the feed. The view is not persisted across launches — the Feed
  always opens as the feed.
- Dismissed postings never mix with the feed: they are excluded from the ordinary list, from a
  company filter, and from a notification reveal.

## Empty & loading states

- No companies yet → friendly empty state pointing at the `+` button ("Add a company to
  start tracking internships").
- Companies added but no postings yet → "No internships found yet. We check every 15
  minutes." + Refresh button.
- First scrape in progress → lightweight skeleton or spinner, not a blocking modal.
- Everything dismissed → "You've dismissed everything" + a **Show dismissed** button, rather
  than the filter-shaped empty state, which would blame a company filter the user never set.
- Dismissed view with nothing in it for the current filter → "Nothing dismissed here" + a
  **Back to the feed** button.

## Behavior details

- The list is driven reactively by the store; when a scrape inserts new postings, they
  appear without a manual reload.
- Rows are keyboard-navigable (↑/↓ to move, Return to open) — nice-to-have, not required.

## Acceptance criteria

- [x] Postings render newest-first by default with company, title, and posted date/time.
- [x] Clicking a row opens the correct posting URL in the browser and clears its NEW badge.
- [x] Company filter narrows the list; "All companies" restores it.
- [x] Sort toggle flips order and the choice survives an app restart.
- [x] The `+` button opens the Add-Company modal.
- [x] New postings from a background scrape appear without user action.
- [x] The `×` dismisses a posting: it leaves the feed, is not deleted, and stays gone after a
      re-scrape and an app restart.
- [ ] Undo restores the posting just dismissed. *(Banner renders correctly; the button itself
      has not been clicked.)*
- [ ] The Dismissed view lists dismissed postings and restores them individually. *(The
      **Dismissed (n)** control renders with the right count; the view has not been opened.)*
