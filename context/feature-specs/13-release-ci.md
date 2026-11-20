# Spec 13 — Release CI (tag → draft GitHub Release)

Depends on: `10` (`release.sh`), `12` (the appcast it writes). No Swift.

## Purpose

Pushing `v<version>` produces a draft GitHub Release holding `Barnacle-<version>.dmg` and
`appcast.xml`, without a release ever depending on one particular Mac's keychain.
`.github/workflows/release.yml` runs `Distribution/release.sh` unchanged in behaviour, so a release
can still be cut by hand with the same script.

## The decision this reverses

Spec `10` kept every credential in the login keychain. CI needs copies of three:
the Developer ID identity, the notary app-specific password, and Sparkle's EdDSA private key. They
are stored as secrets on a GitHub **environment** named `release` whose deployment policy admits
only `v*` tags, so a workflow edited on a branch cannot read them. Still no secret in the repo.

The Developer ID key is the one that matters: anyone holding it can ship software macOS attributes
to you. It was already meant to be exported as a `.p12` for backup (spec `10`, step 0); this is that
same file.

## How the runner signs

- **One throwaway keychain**, unlocked, first in the search list and the default, holding all three
  secrets — so `codesign`, `notarytool`, `generate_keys -p`, and `sign_update` find them the same way
  they find the login keychain locally. Deleted at the end of the job.
- **Release archives now sign manually with Developer ID** (`CODE_SIGN_STYLE=Manual` as a build-
  setting override in `release.sh`, `signingStyle` = `manual` in `ExportOptions.plist`). Automatic
  signing needs an Apple account signed in to Xcode, which a runner doesn't have; manual signing
  needs no provisioning profile because no entitlement here is profile-gated. Debug and the
  project file are untouched. This replaces spec `10`'s archive-with-Apple-Development-then-re-sign
  path for local runs too: one path, tested in both places.
- `release.sh` takes an optional `NOTARY_KEYCHAIN`, passed to `notarytool` as `--keychain`.
- `runs-on: xcode-27` — the Xcode the project is developed with. Apple Silicon only; the binary is
  still universal and `release.sh` refuses one that isn't.
- `fetch-depth: 0`, because the build number is the commit count.

## Why a draft

`SUFeedURL` is `releases/latest/download/appcast.xml`, and a draft is never "latest". So the draft
is the gate spec `10` asks for: download its DMG, try it on a Mac that has never built the project,
then press **Publish** — which is the moment installed copies hear about it.

## One-time setup (by the user)

```sh
# The environment, deployable only from v* tags
gh api -X PUT repos/elizabeth-ling/barnacle/environments/release \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/elizabeth-ling/barnacle/environments/release/deployment-branch-policies \
  -f name='v*' -f type=tag

# Developer ID: Keychain Access → My Certificates → "Developer ID Application: …" → Export (.p12)
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12 --env release
gh secret set DEVELOPER_ID_P12_PASSWORD --env release    # prompts

# Notarization: an app-specific password from account.apple.com
gh secret set NOTARY_APPLE_ID --env release              # prompts
gh secret set NOTARY_PASSWORD --env release              # prompts

# Sparkle (asks for keychain access once)
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle.key
gh secret set SPARKLE_PRIVATE_KEY --env release < sparkle.key && rm sparkle.key
```

Keep `DeveloperID.p12` off this Mac afterwards (that's the spec `10` backup), not in `~/Downloads`.

## Releasing

```sh
git tag v1.2 && git push origin v1.2
```

Then wait for the workflow, test the draft's DMG, and publish. A failed run can be re-run from the
Actions tab; if it failed *after* creating the draft, delete the draft first.

Tags pushed before this workflow existed (`v1.0`, `v1.1`) don't contain it and won't build in CI.

## Acceptance criteria

- [x] `release.sh` archives and exports with manual Developer ID signing; the export is signed
      `Developer ID Application`, timestamped, hardened, universal, without `get-task-allow`
      (checked locally, 2026-11-19, without notarization).
- [ ] The `release` environment exists, admits only `v*` tags, and holds the five secrets.
- [ ] Pushing a tag produces a draft release with the DMG and `appcast.xml`, and the job's
      `spctl` / `stapler` checks pass on the runner.
- [ ] The draft's DMG installs on a second Mac; after publishing, an installed older copy offers
      the update.
