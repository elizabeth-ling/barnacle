#!/bin/bash
#
# Builds a notarized, stapled build/Barnacle-<version>.dmg and the build/appcast.xml that tells
# installed copies about it. See specs 10 and 12.
#
#   git tag v1.0 && Distribution/release.sh 1.0
#
# One-time setup, by hand (both secrets stay in the login keychain):
#   xcrun notarytool store-credentials barnacle --apple-id <appleid> --team-id ART77YDPX6
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys   # Sparkle's EdDSA key
#
# Pushing the tag also runs this in CI (.github/workflows/release.yml, spec 13), which loads the
# same secrets into a throwaway keychain and sets NOTARY_KEYCHAIN to it.
#
# The version is stated here and nowhere else: it reaches the app as a build setting override.
# The build number is the commit count, which only rises as long as main's history isn't rewritten.

set -euo pipefail

readonly TEAM_ID="ART77YDPX6"
readonly BUNDLE_ID="com.elizabeth.barnacle"
readonly NOTARY_PROFILE="barnacle"
readonly REPO_URL="https://github.com/elizabeth-ling/barnacle"
readonly PACKAGES_DIR="build/SourcePackages"
readonly SPARKLE_BIN="$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"

# Locally the profile is in the login keychain; CI names the throwaway keychain that holds it.
notary_auth=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    notary_auth+=(--keychain "$NOTARY_KEYCHAIN")
fi

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

# Zips what notarytool won't take bare, submits, and on rejection prints Apple's reason, because
# `notarytool log` is the only thing that says why.
notarize() {
    local file=$1 upload=$1 output status id

    if [[ -d "$file" ]]; then
        upload="$file.zip"
        ditto -c -k --keepParent "$file" "$upload"
    fi

    # Stderr stays on the terminal: anything in it would corrupt the JSON parsed below.
    output=$(xcrun notarytool submit "$upload" "${notary_auth[@]}" --wait \
        --output-format json) || true
    status=$(plutil -extract status raw -o - - <<<"$output" 2>/dev/null) || status=""
    id=$(plutil -extract id raw -o - - <<<"$output" 2>/dev/null) || id=""

    if [[ "$status" != "Accepted" ]]; then
        echo "$output" >&2
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
            echo "Fetch this log again with: xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE" >&2
        fi
        fail "notarization of $(basename "$file") ended with status '${status:-unknown}'"
    fi
}

# Passes only if `pattern` appears in `text`, naming the check that failed otherwise.
expect() {
    local check=$1 pattern=$2 text=$3
    grep -Eq "$pattern" <<<"$text" || fail "$check: expected '$pattern' in:"$'\n'"$text"
}

verify() {
    local app=$1 dmg=$2 details

    codesign --verify --deep --strict --verbose=2 "$app"

    details=$(codesign -dv --verbose=4 "$app" 2>&1)
    expect "app signature" '^Authority=Developer ID Application' "$details"
    expect "app signature" '^Timestamp=' "$details"
    expect "app signature" '^CodeDirectory .*flags=.*runtime' "$details"

    expect "app Gatekeeper" 'source=Notarized Developer ID' "$(spctl -a -vvv -t exec "$app" 2>&1)"
    expect "DMG Gatekeeper" 'accepted' \
        "$(spctl -a -vvv -t open --context context:primary-signature "$dmg" 2>&1)"

    xcrun stapler validate "$app"
    xcrun stapler validate "$dmg"

    local archs
    archs=$(lipo -archs "$app/Contents/MacOS/Barnacle")
    expect "universal binary" 'x86_64' "$archs"
    expect "universal binary" 'arm64' "$archs"

    # Changing this orphans every user's sandbox container, and their store with it.
    [[ "$(defaults read "$PWD/$app/Contents/Info" CFBundleIdentifier)" == "$BUNDLE_ID" ]] ||
        fail "the bundle identifier is no longer $BUNDLE_ID"
}

[[ $# -eq 1 ]] || fail "usage: Distribution/release.sh <version>, e.g. 1.0"
readonly VERSION=$1
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "'$VERSION' is not a version like 1.0 or 1.0.1"

cd "$(dirname "$0")/.."

# A DMG that can't be traced to a commit is unsupportable.
[[ -z "$(git status --porcelain)" ]] || fail "the working tree is dirty; commit or stash first"
tag_commit=$(git rev-parse -q --verify "refs/tags/v$VERSION^{commit}") ||
    fail "tag v$VERSION doesn't exist; run: git tag v$VERSION"
[[ "$tag_commit" == "$(git rev-parse HEAD)" ]] || fail "tag v$VERSION isn't on the current commit"

# The hash rather than the name, because a renewed certificate would make the name ambiguous.
identities=$(security find-identity -v -p codesigning)
identity=$(awk -v team="($TEAM_ID)" \
    '/Developer ID Application:/ && index($0, team) { print $2; exit }' <<<"$identities")
[[ -n "$identity" ]] || fail "no Developer ID Application identity for team $TEAM_ID in the keychain"

if ! profile_check=$(xcrun notarytool history "${notary_auth[@]}" 2>&1); then
    echo "$profile_check" >&2
    fail "can't use the notary profile '$NOTARY_PROFILE'. If it's missing, create it once with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <appleid> --team-id $TEAM_ID"
fi

# Resolved into a known directory so Sparkle's signing tools are at a fixed path.
xcodebuild -quiet -resolvePackageDependencies -scheme Barnacle -clonedSourcePackagesDirPath "$PACKAGES_DIR"
[[ -x "$SPARKLE_BIN/sign_update" ]] || fail "Sparkle's tools aren't in $SPARKLE_BIN"

# An app whose SUPublicEDKey doesn't match the keychain's private key can never accept an update,
# and nobody finds out until the release after this one. Refuse now instead.
sparkle_key=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null) ||
    fail "no Sparkle signing key in the keychain; create one once with: $SPARKLE_BIN/generate_keys"
[[ "$(plutil -extract SUPublicEDKey raw -o - Barnacle/Info.plist)" == "$sparkle_key" ]] ||
    fail "SUPublicEDKey in Barnacle/Info.plist doesn't match the keychain's Sparkle key ($sparkle_key)"

readonly ARCHIVE="build/Barnacle.xcarchive"
readonly EXPORT_DIR="build/export"
readonly STAGE_DIR="build/stage"
readonly APP="$EXPORT_DIR/Barnacle.app"
readonly DMG="build/Barnacle-$VERSION.dmg"
readonly APPCAST="build/appcast.xml"

rm -rf "$ARCHIVE" "$EXPORT_DIR" "$STAGE_DIR" "$DMG" "$APPCAST"

step "Archiving $VERSION"
# Archiving, not building: only an archive strips get-task-allow, and notarization refuses it.
# Signed manually with Developer ID, overriding the project's automatic Apple Development signing:
# automatic signing needs an Apple account signed in to Xcode, which CI doesn't have, and rejects a
# Developer ID identity outright. Manual signing needs neither, because no entitlement here is
# profile-gated. Debug builds are untouched.
xcodebuild -quiet -scheme Barnacle -configuration Release -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" -clonedSourcePackagesDirPath "$PACKAGES_DIR" archive \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)"

step "Exporting with Developer ID"
xcodebuild -quiet -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist Distribution/ExportOptions.plist \
    -exportPath "$EXPORT_DIR"

step "Notarizing and stapling the app"
# Stapled before packaging, so the copy dragged to /Applications verifies offline forever.
notarize "$APP"
xcrun stapler staple "$APP"

step "Building the DMG"
mkdir -p "$STAGE_DIR"
ditto "$APP" "$STAGE_DIR/Barnacle.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -quiet -volname Barnacle -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG"
codesign --sign "$identity" --timestamp "$DMG"

step "Notarizing and stapling the DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

step "Verifying"
verify "$APP" "$DMG"

step "Writing the appcast"
# Signs the DMG exactly as uploaded: stapling changes its bytes, so this has to come after it.
# One item is enough — Sparkle only needs to hear about the newest build.
signature=$("$SPARKLE_BIN/sign_update" "$DMG")
build_number=$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")
cat >"$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Barnacle</title>
    <item>
      <title>Barnacle $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build_number</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO_URL/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url="$REPO_URL/releases/download/v$VERSION/Barnacle-$VERSION.dmg"
                 type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$APPCAST"

echo
echo "Built $DMG and $APPCAST. Now test the DMG on a Mac that has never built this project."
echo "Publish both together — installed copies read the appcast from the latest release:"
echo "  gh release create v$VERSION $DMG $APPCAST"
