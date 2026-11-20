# Spec 12 — Auto-Update (Sparkle)

Depends on: `10` (a notarized, Developer ID–signed DMG is what Sparkle installs), `11` (the GitHub
Release the DMG lives in), `09` (the onboarding step that asks).

## Purpose

Once someone has Barnacle installed, getting them a new version should not depend on them going
back to the README. Barnacle checks for a new version once a day and, unless the user said
otherwise during onboarding, downloads it in the background and installs it the next time the app
quits.

## How

**Sparkle 2**, via SPM. It is the third dependency (after `HotKey` and `SwiftSoup`), and the only
one that ships code the user runs outside the app process, which is why it gets its own spec.

- **Feed:** `SUFeedURL` is `https://github.com/elizabeth-ling/barnacle/releases/latest/download/appcast.xml`.
  `latest/download` always redirects to the newest non-prerelease release, so the appcast is
  uploaded to each release next to the DMG and there is no other host. This is the one place
  spec `11`'s "versioned URLs only" rule does not apply: an update feed must point at "latest".
- **Signing:** an EdDSA key in the login keychain (`generate_keys`), with its public half in
  `Barnacle/Info.plist` as `SUPublicEDKey`. `release.sh` refuses to build if the two disagree,
  because a mismatch is otherwise discovered one release too late: by an app that can never
  accept an update.
- **Sandbox:** Barnacle is sandboxed, so `SUEnableInstallerLauncherService` is on and the
  entitlements carry the two `mach-lookup` temporary exceptions (`$(PRODUCT_BUNDLE_IDENTIFIER)-spks`,
  `-spki`). The downloader XPC service is not enabled, because the app already has
  `network.client`. Both XPC services ship inside `Sparkle.framework`, and the Developer ID export
  re-signs them.
- **Appcast:** `release.sh` signs the stapled DMG with `sign_update` and writes a one-item
  `build/appcast.xml`. Sparkle only needs to hear about the newest build. `sparkle:version` is
  the build number (`CFBundleVersion`, the commit count), which only rises.
- **Debug builds never start the updater**, because one would offer to replace the build Xcode just
  made with whatever is on the Releases page.

## The one setting

**Install updates automatically**, on by default.

- **On:** Sparkle checks daily, downloads in the background, and installs when Barnacle quits or the
  Mac restarts. This is `SUAutomaticallyUpdate`.
- **Off:** Sparkle still checks daily, but it shows its own "A new version is available" window and
  waits for the user.

**Sparkle owns the value.** `UpdateController` mirrors `SPUUpdater.automaticallyDownloadsUpdates`
for SwiftUI rather than keeping its own key in `UserDefaults`, so there is no second copy to drift
from what Sparkle actually does. `Info.plist` also sets `SUEnableAutomaticChecks`, which stops
Sparkle from showing its own "check automatically?" prompt on the second launch. The question is
asked once, in onboarding, by us.

Not offered: turning checks off entirely. A personal app that silently goes stale is the problem
this spec exists to fix.

## Where it appears

- **Onboarding, step 4:** "Keep Barnacle up to date?", with the switch and one sentence explaining
  it. This step comes last because it is housekeeping. Skip from any earlier step leaves the
  default (on). It writes the same Sparkle setting Settings does, so onboarding still owns no state
  (spec `09`).
- **Settings → Updates:** the same `AutoUpdateToggle`, a **Check for Updates** button, and the
  running version.
- **Menu bar:** **Check for Updates…**, the conventional place for it.

## Caveat worth knowing

Barnacle lives in the menu bar and rarely quits, so a silently downloaded update can wait until a
restart or logout. That is acceptable: the update is already downloaded and verified. A manual
**Check for Updates** offers to install it right away.

## Bootstrap

Only copies that already contain Sparkle can update themselves. No release had been published when
this landed, so v1.0 is the first and everyone starts updatable. If that turns out to be wrong,
earlier copies need one manual re-download.

## Acceptance criteria

- [x] Sparkle 2 is an SPM dependency; `Sparkle.framework` with `Installer.xpc` and `Downloader.xpc`
      is embedded in the built app.
- [x] The built `Info.plist` carries `SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService`,
      `SUEnableAutomaticChecks`, and `SUAutomaticallyUpdate`; the signed entitlements carry both
      `mach-lookup` exceptions.
- [x] `SUPublicEDKey` matches the keychain's private key (`generate_keys -p`).
- [ ] `release.sh` writes an appcast whose signature verifies against the uploaded DMG.
- [ ] Onboarding's step 4 and Settings' switch show and change the same value.
- [ ] An installed release finds a newer one on GitHub and installs it, both with the switch on
      (on quit) and off (via the dialog), with the sandbox in place.
- [x] `xcodebuild -scheme Barnacle -configuration Debug build` and the Release build succeed with
      no new warnings.
