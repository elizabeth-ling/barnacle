# Spec 10 — Release Packaging (Developer ID → notarized DMG)

Depends on: nothing in the app. This spec touches build settings, a script, and an Apple account —
no Swift. **Build any time.** It is the only thing standing between the finished app and a person
who is not you being able to run it.

## Purpose

Turn `Barnacle.app` into a file a stranger can download, drag into Applications, and open — with no
Terminal, no right-click-Open, and no "Apple cannot check it for malicious software."

The whole spec exists to satisfy one sentence: **Gatekeeper must be able to verify the app without
the internet's permission and without the user's help.** Everything below is the price of that
sentence.

## The decision that costs money

Distribution outside the Mac App Store requires a **Developer ID Application** certificate, and that
certificate requires a **paid Apple Developer Program membership ($99/yr)**. There is no free path
to the experience described above.

The two free alternatives, both rejected:

- **Ad-hoc / unsigned DMG.** The user gets "Barnacle is damaged and can't be opened" or "cannot be
  opened because Apple cannot check it," and has to right-click → Open or run `xattr -d`. We already
  know what ad-hoc signing costs us: spec `04`'s notifications were silently dead for two days
  because macOS refuses `requestAuthorization` for an ad-hoc-signed app, and every rebuild appended
  another stale designated requirement to `ncprefs`. Shipping that to someone else's Mac ships that
  bug to them.
- **Ship the source, let people build it.** Fine for a personal tool, incompatible with "go to my
  page, press download."

So: **pay, or change the ask.** The rest of this spec assumes paid.

### Step 0 — confirm the account tier

The keychain currently holds exactly one identity, `Apple Development: Elizabeth Ling (XJ78Q52STA)`,
team `ART77YDPX6`. An Apple Development cert is issued to free accounts too, so its presence proves
nothing about the tier.

Check at developer.apple.com/account → Certificates, IDs & Profiles → Certificates → `+`. If
**Developer ID Application** is offered, the membership is paid. If it is missing, the account is
free and must enroll first (approval is typically same-day to 48h).

Create the certificate through **Xcode → Settings → Accounts → Manage Certificates → `+` → Developer
ID Application**, not the web portal — Xcode generates and keeps the private key locally, which is
the half that matters.

**Back the identity up immediately** (Keychain Access → export both the cert and its private key as
a `.p12`, store it off this Mac). Losing the private key means every future release is signed by a
different identity, which macOS treats as a different developer. Developer ID certs are capped at
five per team and last five years.

## Build settings

Change as little as possible. The app is already shaped correctly.

| Setting | Value | Why |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.elizabeth.barnacle` — **unchanged** | It names the sandbox container. Changing it orphans every user's store, ours included. |
| `ENABLE_HARDENED_RUNTIME` | `YES` (already set) | Notarization refuses anything else. |
| `CODE_SIGN_IDENTITY` (Release) | `Developer ID Application` | Debug keeps `Apple Development`. |
| `CODE_SIGN_STYLE` | `Automatic`, team `ART77YDPX6` | No provisioning profile is needed: nothing here uses a profile-gated entitlement. |
| `MARKETING_VERSION` | the user-visible release number | Appears in the DMG filename and on the page. Bump every release. |
| `CURRENT_PROJECT_VERSION` | monotonic integer | Bump every release, including re-cuts of the same marketing version. |

**Keep the app sandbox.** It is not required outside the App Store, but `Barnacle.entitlements` is
already minimal and correct (`app-sandbox`, `network.client`, `files.user-selected.read-only`), the
app demonstrably works inside it, and turning it off to make packaging easier would be trading a
security property for nothing. The Carbon global hotkey behind `⌘J` (`RegisterEventHotKey`) is
sandbox-legal and needs no Accessibility grant — but see the verification list; it is the headline
feature and must be re-confirmed on the notarized build.

The archive build is what strips `get-task-allow`. A `Debug` build can never be notarized, so
release goes through `archive`, never through the plain `build` the project uses day to day.

## The pipeline

Six steps, in this order. `Distribution/release.sh <version>` implements them.

1. **Archive.**
   `xcodebuild -scheme Barnacle -configuration Release -archivePath build/Barnacle.xcarchive archive`
2. **Export** with `Distribution/ExportOptions.plist` — `method` = `developer-id`, `teamID` =
   `ART77YDPX6`, `signingStyle` = `automatic`, `destination` = `export`. Add
   `-allowProvisioningUpdates` so automatic signing can work from the CLI.
3. **Notarize the app.** `notarytool` will not accept a bare bundle, so zip it first with
   `ditto -c -k --keepParent Barnacle.app Barnacle.zip`, then
   `xcrun notarytool submit Barnacle.zip --keychain-profile barnacle --wait`.
4. **Staple the app.** `xcrun stapler staple Barnacle.app`.
5. **Build the DMG** from a staging folder holding the *stapled* app plus a symlink to
   `/Applications`: `hdiutil create -volname Barnacle -srcfolder stage -ov -format UDZO
   Barnacle-<version>.dmg`. Sign it: `codesign --sign "Developer ID Application: …" --timestamp`.
6. **Notarize and staple the DMG** the same way as step 3–4.

### Why the app is stapled before it is packaged

The notarization ticket lives outside the signature; stapling copies it into the bundle. Stapling
only the DMG leaves the app that gets dragged to `/Applications` with no local ticket, so its first
launch depends on an online lookup — which fails on a plane, on a locked-down network, or during an
Apple outage, and fails in the most alarming possible way. Doing both is a few seconds of build time
for an app that verifies offline forever.

### Credentials

Once, by hand: `xcrun notarytool store-credentials "barnacle" --apple-id <appleid> --team-id
ART77YDPX6 --password <app-specific-password>`, where the password is generated at
account.apple.com → Sign-In and Security → App-Specific Passwords.

That command puts the secret in the login keychain and everything afterwards refers to it as
`--keychain-profile barnacle`. **No Apple credential ever appears in the repo, the script, or a
shell history.** The script fails with a readable message if the profile is missing rather than
prompting mid-pipeline.

### The script's own rules

- Takes the version as its one argument, and writes it into `MARKETING_VERSION` via `agvtool` or a
  build setting override — the version is stated once, not in three files that drift.
- Refuses to run on a dirty working tree or a non-tagged commit, because a DMG that cannot be traced
  to a commit is unsupportable.
- Prints the notarization log URL on failure. `notarytool log <id>` is the only thing that says
  *why* Apple rejected a submission, and the failure is almost always one un-hardened nested binary.
- Leaves everything in `build/`, which is git-ignored. The DMG is never committed — see spec `11`.

## Verification

Local checks, all of which must pass before the DMG is uploaded anywhere:

- `codesign --verify --deep --strict --verbose=2 Barnacle.app` — no output but "valid on disk".
- `codesign -dv --verbose=4 Barnacle.app` — authority chain starts `Developer ID Application`, a
  `Timestamp=` line is present, and `flags` includes `runtime`.
- `spctl -a -vvv -t exec Barnacle.app` → `accepted`, `source=Notarized Developer ID`.
- `spctl -a -vvv -t open --context context:primary-signature Barnacle-<version>.dmg` → `accepted`.
- `xcrun stapler validate` on both the app and the DMG.
- `lipo -archs Barnacle.app/Contents/MacOS/Barnacle` → `x86_64 arm64`. Release archives are
  universal by default, but an Intel user finding out otherwise is a silent, total failure.

**The only honest end-to-end test is a second Mac** (or at minimum a fresh user account) that has
never built this project, downloading from the real URL over HTTPS. `spctl` on the build machine
does not exercise quarantine, and quarantine is the thing that breaks. Barring a second Mac,
`xattr -w com.apple.quarantine "0083;00000000;Safari;" Barnacle-<version>.dmg` before opening it
approximates the download.

On that machine, confirm the app itself still works after the trip: the feed scrapes, a notification
is delivered, and **⌘J opens the overlay over a full-screen app**. A sandboxed, notarized, quarantined
copy is a different execution context than the one every previous spec was verified in.

### Expect one dialog

A notarized, quarantined app still shows **"Barnacle is an app downloaded from the Internet. Are you
sure you want to open it?"** on first launch, with an **Open** button. That is correct and final —
it is not a sign that notarization failed. "Apple could not verify…" or "…is damaged" *is*.

### Expect to re-allow notifications on this Mac

Switching the signature from Apple Development to Developer ID changes the app's designated
requirement, which is the same thing that invalidated the notification grant in spec `04`. On the
development Mac, expect to allow Barnacle once more in System Settings → Notifications. Downloaded
copies are unaffected — they see one stable identity from their first launch onward, which is the
entire point.

## Non-goals

- **Mac App Store.** Different certificate, review, and a receipt check; nothing here is wasted if
  it ever happens, but it is not this spec.
- **Auto-update.** See below.
- **Homebrew cask, `pkg` installer, MDM.** A DMG is what the ask describes.
- **Crash reporting or analytics.** This is still a single-user app that happens to be downloadable.

## Later, deliberately not now

**Sparkle** is the answer to "how do users get 1.1." It needs an EdDSA key pair, an `appcast.xml`
served from the same host as the DMG, `SUFeedURL` in the Info.plist, and — because Barnacle is
sandboxed — Sparkle 2's XPC services bundled and signed alongside the app. That is a real spec, not
a checkbox. Until it exists, a new version means re-downloading from the page, which is fine at this
scale and is exactly what spec `11` tells the user.

## Acceptance criteria

- [ ] A **Developer ID Application** certificate exists and its private key is backed up off this Mac.
- [ ] Release builds are signed with it; Debug still uses Apple Development.
- [ ] `Distribution/release.sh <version>` produces `build/Barnacle-<version>.dmg` from a clean tree
      in one command, with no secret in the repo.
- [ ] `spctl -a -t exec` on the exported app reports `source=Notarized Developer ID`.
- [ ] `stapler validate` passes on both the app and the DMG.
- [ ] The binary is universal (`x86_64 arm64`).
- [ ] On a Mac that has never built the project: the downloaded DMG mounts, drag-to-Applications
      works, and first launch shows only the ordinary "downloaded from the Internet" prompt.
- [ ] On that same Mac: a scrape delivers a notification and `⌘J` opens the overlay over a
      full-screen app.
- [ ] The bundle identifier is unchanged, and an existing local install keeps its data across the
      upgrade.
