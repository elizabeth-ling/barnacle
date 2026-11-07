# Spec 11 — Download from the README

Depends on: `10` (there is nothing to link to until the DMG is notarized). **Build after `10`.**

## Purpose

Make `README.md` the download page: what Barnacle is, a screenshot, and a link that hands over the
DMG. It exists so the answer to "can I try it?" is a URL instead of a conversation — and the URL is
`github.com/elizabeth-ling/barnacle`, which is the link that gets shared anyway.

**There is no separate website.** No static HTML, no CSS, no GitHub Pages, no Vercel project. The
repository page *is* the landing page. That decision costs the design control described below and
buys never deploying, never renewing a domain, and never having a page that has drifted from the
release it points at.

## The rule that keeps this small

**The README is a link and a promise, nothing else.** No account, no email capture, no analytics, no
changelog, no badge wall. Everything on it is either a sentence a stranger needs before downloading,
a picture, or a link.

## Where the bytes live

- **The DMG lives in a GitHub Release**, published by `gh release create v<version>
  build/Barnacle-<version>.dmg`. It is 10–40MB of binary that changes every release, which is
  exactly what a Git repository is worst at storing. Releases are free, fast, and give a permanent
  per-version URL.
- **The README lives in the repository root**, rendered by GitHub. No host, no deploy step.
- **The screenshots live in the repository**, under `Design/screenshots/`, referenced by relative
  path so they render on the repo page and in any fork. These are the one binary exception to the
  rule above: two PNGs of a few hundred KB that change rarely, not a 40MB DMG that changes every
  release. Keep them under ~500KB each; GitHub proxies them through its image cache, and a slow
  screenshot is a blank space where the proof is supposed to be.

The README links to the **versioned** asset URL, not `releases/latest/download/…`. A versioned URL
means a link someone shared last month still resolves to the build they were talking about, and it
makes "which version do you have?" answerable. The cost is one line of the README changing per
release — so `release.sh` (spec `10`) rewrites the version string and the link, since it already
knows the version. The README is never hand-edited for a release.

**Ordering problem, and its answer.** `release.sh` refuses to run on a dirty tree or an untagged
commit, and the README edit dirties the tree. So the rewrite is the *last* step of the script, after
notarization and after `gh release create` has proven the asset URL resolves: edit `README.md`,
commit it as `chore: link release v<version>`, push. The tagged commit stays the one the DMG was
built from; the README commit sits after it, pointing back at it. Rewriting the README *before*
tagging would publish a link to an asset that does not exist yet if any later step fails.

Serving requirements, all satisfied by GitHub Releases and worth checking once: **HTTPS**, the
filename preserved verbatim (`Barnacle-1.0.dmg`), and no redirect chain that re-wraps the file.
Release asset downloads redirect once to object storage and hand back the bytes unchanged, which is
what keeps the signature and the stapled ticket intact.

## What the README says

The README has two audiences now — someone deciding whether to download, and someone reading the
source. **The download comes first.** A person who wants the code will scroll; a person deciding in
ten seconds will not.

At the top:

- The name and the tagline already there, plus one sentence: *tracks internship postings from the
  companies you pick, tells you when something new appears, and logs what you applied to.*
- **A screenshot of the Feed.** It is the screen the app is; a download link with no picture asks
  for more trust than a stranger has.
- The link: **Download for macOS** — as a heading-sized link, with `v<version>` and **Requires macOS
  14 or later** on the line beneath it. The requirement belongs next to the link, not in a footnote,
  because it is the one reason the download can be wasted.

Then, in this order:

1. **Install** — three steps, one line each: open the DMG, drag Barnacle to Applications, open it
   from Applications. Then: *the first launch asks "are you sure you want to open it?" — that is
   macOS's standard prompt for anything downloaded. Click Open.* Naming the dialog in advance is
   what stops it from reading as a warning.
2. **What it does** — three or four lines with the second screenshot (`⌘J` over another app, which
   is the feature that is hard to believe from text alone).
3. **What it asks for** — it requests permission to send notifications, and it talks to the careers
   pages of the companies you add. Nothing else, no account, and the data stays on the Mac. Short,
   plain, and true; a downloaded background app that watches the network should say so unprompted.
4. **Build it yourself** — the developer section, last: requirements, `open Barnacle.xcodeproj`, and
   a pointer to `context/` for the specs. This replaces the current "tech stack" and "todo" lines.

Nothing about updates beyond a line saying new versions appear on the Releases page and are
installed by downloading again, which is honest until Sparkle exists (spec `10`, "Later").

**The release notes carry the install steps too.** Someone linked straight to
`/releases/tag/v1.0` never sees the README, so `gh release create --notes` gets the same three lines
and the same sentence about the first-launch prompt. It is four lines of duplication that prevents
the only other landing page from being a bare file list.

## The instruction that must not appear

**No right-click → Open. No `xattr -d com.apple.quarantine`. No "if macOS says the app is damaged,
try…".**

If any of that is needed, notarization is broken and the fix is in spec `10`, not in the README.
Publishing the workaround hides the bug, teaches every visitor to bypass Gatekeeper as a matter of
routine, and makes the app indistinguishable from something that could not be notarized. A README is
*more* likely to attract this than a landing page would be, because that is where open-source
projects habitually put it. The "downloaded from the Internet" prompt in the Install steps is the
*only* macOS dialog the README acknowledges.

## Design

**Spec `06`'s palette and type do not survive this move, and that is accepted.** GitHub renders
Markdown in its own fonts and colours and strips `<style>` blocks, `class`, and inline `style`
attributes, so there is no warm-grey ground, no New York serif, and no `#D97757` accent — trying to
recreate them is a fight with a sanitizer that cannot be won.

What carries the app's look instead:

- **The screenshots.** They are the only part of the page rendered by us rather than by GitHub, so
  they are the whole visual argument. Shoot them from the real app at a retina scale, on the light
  scheme the app is pinned to, cropped to the window with no desktop clutter behind it.
- **Structure.** Short sections, one `##` each, no wall of prose — the same density the app has.

Constrain the HTML to what GitHub actually renders: `<img>` with `width`, `<picture>`, `<details>`,
and `<div align>`. Everything else is either stripped or unreliable. The README must read correctly
as **plain text** as well, because that is what `gh repo view`, editors, and forks show.

GitHub serves the page in both light and dark themes. The screenshots are light-only and stay that
way — a light screenshot on a dark page reads as a window, not a bug — so there is no
`prefers-color-scheme` `<picture>` swap and no second set of assets to keep in sync.

## Non-goals

- A separate website, static site generator, GitHub Pages, or custom domain.
- Analytics, telemetry, download counters, email capture, a newsletter.
- A badge wall — CI, licence, stars, downloads. None of them help someone decide to download.
- A changelog, blog, docs site, or FAQ. The Releases page is the changelog.
- An update feed or version-check endpoint (spec `10` covers why).
- Windows or Linux anything.
- Any server-side code.

## Acceptance criteria

- [ ] `README.md` opens with the one-sentence description, the Feed screenshot, and the download
      link — above the developer section, and visible without scrolling past a badge wall.
- [ ] The DMG is attached to a GitHub Release; the repository contains no `.dmg` and no `.app`.
      Screenshots under `Design/screenshots/` are the only committed binaries.
- [ ] The download link is the versioned asset URL and is rewritten by `release.sh`, not by hand,
      as a commit made *after* the release is published.
- [ ] The downloaded file arrives with its filename and signature intact — `spctl` and `stapler
      validate` pass on the copy downloaded from the Release URL, not just the built one.
- [ ] The README states the macOS 14 requirement adjacent to the download link.
- [ ] The install steps name the "downloaded from the Internet" prompt and contain no Gatekeeper
      workaround — in the README *and* in the release notes.
- [ ] Both screenshots render on the GitHub repo page (not a broken-image icon), in both the light
      and dark GitHub themes.
- [ ] The README is readable as plain text, with no stripped-out HTML leaving a gap.
- [ ] A person who has never seen the project can go from the repo page to a running app with a
      mouse only — no Terminal, no instructions from the author.
