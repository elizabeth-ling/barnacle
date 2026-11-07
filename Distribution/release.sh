#!/bin/bash
#
# Builds a notarized, stapled build/Barnacle-<version>.dmg. See spec 10.
#
#   git tag v1.0 && Distribution/release.sh 1.0
#
# One-time setup, by hand (the secret stays in the login keychain):
#   xcrun notarytool store-credentials barnacle --apple-id <appleid> --team-id ART77YDPX6
#
# The version is stated here and nowhere else: it reaches the app as a build setting override.
# The build number is the commit count, which only rises as long as main's history isn't rewritten.

set -euo pipefail

readonly TEAM_ID="ART77YDPX6"
readonly BUNDLE_ID="com.elizabeth.barnacle"
readonly NOTARY_PROFILE="barnacle"

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
    output=$(xcrun notarytool submit "$upload" --keychain-profile "$NOTARY_PROFILE" --wait \
        --output-format json) || true
    status=$(plutil -extract status raw -o - - <<<"$output" 2>/dev/null) || status=""
    id=$(plutil -extract id raw -o - - <<<"$output" 2>/dev/null) || id=""

    if [[ "$status" != "Accepted" ]]; then
        echo "$output" >&2
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
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

if ! profile_check=$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1); then
    echo "$profile_check" >&2
    fail "can't use the notary profile '$NOTARY_PROFILE'. If it's missing, create it once with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <appleid> --team-id $TEAM_ID"
fi

readonly ARCHIVE="build/Barnacle.xcarchive"
readonly EXPORT_DIR="build/export"
readonly STAGE_DIR="build/stage"
readonly APP="$EXPORT_DIR/Barnacle.app"
readonly DMG="build/Barnacle-$VERSION.dmg"

rm -rf "$ARCHIVE" "$EXPORT_DIR" "$STAGE_DIR" "$DMG"

step "Archiving $VERSION"
# Archiving, not building: only an archive strips get-task-allow, and notarization refuses it.
# This signs with Apple Development; the export below re-signs with Developer ID. Automatic signing
# rejects a Developer ID identity at this stage, so the project's settings can't name it.
xcodebuild -quiet -scheme Barnacle -configuration Release -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" archive \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)"

step "Exporting with Developer ID"
xcodebuild -quiet -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist Distribution/ExportOptions.plist \
    -exportPath "$EXPORT_DIR" -allowProvisioningUpdates

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

echo
echo "Built $DMG. Now test it on a Mac that has never built this project."
