# Spec 04 — Notifications

Depends on: `01` (emits new postings).

## Purpose

Alert the user when a new internship posting is detected. Native macOS notifications are the
default (free, zero-setup). SMS to the user's phone is an optional add-on.

## Native notifications (default)

- Use the `UserNotifications` framework. Request authorization on first launch.
- After each scrape run, the `ScrapeCoordinator` hands the batch of new postings to
  `NotificationService`.
- Batching rules:
  - 1 new posting → one notification: **"New internship at {Company}"** / body = job title.
  - 2+ new postings in one run → one summary notification: **"{n} new internships"** / body
    lists up to ~3 "{Company} — {title}" lines, then "and N more."
- Clicking a notification opens the app to the Feed (ideally scrolled to / filtered on the
  new items). If it's a single posting, it may open that posting's URL directly.
- Never notify for postings already seen (dedup is upstream in spec `01`, so the notifier
  can trust that everything handed to it is genuinely new).
- Respect a "notifications on/off" toggle in Settings.

## Optional phone notifications (reach the user's iPhone)

Off by default. Used to alert the user on their **iPhone** when they're away from the Mac.
The general contract for every option below: send **one message per scrape batch** (not one
per posting), use the same summary text as the native notification, and treat failures as
non-blocking — the native macOS notification always fires regardless.

### Recommended: ntfy (free, native iOS app)

This is the default phone path. Simplest to build and reliable.

- The user installs the **ntfy** iOS app and subscribes to a topic.
- Settings stores a **topic name** (or full server URL for self-hosters). The app should
  offer to **generate a long random topic** so it isn't guessable — public ntfy topics are
  readable/writable by anyone who knows the name.
- On a new-posting batch, POST via `URLSession` to `https://ntfy.sh/{topic}` with the
  summary as the body and a title header. That's the whole integration — no account, no
  credentials, no per-message cost.

### Alternative: Twilio SMS

For a true SMS text instead of a push.

- Settings collects Twilio **Account SID**, **Auth Token**, **From number**, and the user's
  **To number**. Store credentials in the macOS **Keychain**, not plain files.
- On a new-posting batch, POST to `https://api.twilio.com/2010-04-01/Accounts/{SID}/Messages.json`
  with Basic auth (SID:AuthToken), `From`, `To`, and a short `Body`.
- Trade-off: requires a Twilio account, a provisioned number (~$1/month), and a tiny
  per-message cost.

### Not recommended: iMessage

The user has an iPhone, so iMessage seems natural — but **don't build on it.** The only way
a Mac app can send an iMessage is by automating the Messages app via AppleScript, and Apple
has degraded/broken Messages scripting on recent macOS (the `send` command is unreliable;
UI-scripting workarounds are brittle and need Automation permission). It also requires
Messages to be running and signed in. Delivery to the user's own number works in principle,
but the mechanism is too fragile for a core feature. Prefer ntfy. If the agent still wants to
attempt it, keep it strictly behind a clearly-labeled "experimental" toggle that falls back
to native + ntfy on any failure.

> Setup note for the user: the native notification path needs no setup and is on by default.
> If they want alerts on their iPhone when away from the Mac, **ntfy** is the easy path —
> install the iOS app, pick a topic, done. Twilio is there if they specifically want an SMS
> text rather than a push.

## Acceptance criteria

- [x] First launch requests notification permission.
- [x] A single new posting produces one native notification with company + title.
- [x] Multiple new postings in one run produce one summary notification.
- [ ] Clicking a notification brings the app forward to the relevant Feed items.
- [x] No notification fires on a scrape that found nothing new.
- [ ] With phone notifications enabled (ntfy), one message per new-posting batch reaches the
      user's iPhone; a random topic can be generated; failure still leaves the native
      notification intact. (Twilio, if used, follows the same one-per-batch contract with
      credentials in Keychain.)
