#!/bin/sh
# Builds the universal app, notarizes it when it's signed with the Developer ID, and writes
# dist/Chip-Pops-<version>.zip for a GitHub release, with Chip Pops.app at the top.
# Needs the Developer ID certificate in the keychain and a notarytool profile named "notary":
#   xcrun notarytool store-credentials notary --apple-id <apple id> --team-id DGFKNTAG99
# Usage: ./Scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *public static let version = "\(.*\)"$/\1/p' Sources/BlipsCore/Version.swift)
APP="$ROOT/dist/Chip Pops.app"
ZIP="$ROOT/dist/Chip-Pops-$VERSION.zip"
STAGE=$(mktemp -d)
CHECK=$(mktemp -d)
trap 'rm -rf "$STAGE" "$CHECK"' EXIT

rm -f "$ZIP"
./Scripts/build-app.sh >/dev/null
lipo "$APP/Contents/MacOS/Chip Pops" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/blips" -verify_arch arm64 x86_64

TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [ "$TEAM" = DGFKNTAG99 ]; then
  SIGNATURE="Developer ID"
  # The build is reproducible, so a rebuild Apple already notarized staples right away.
  if ! xcrun stapler staple "$APP" >/dev/null 2>&1; then
    ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
    RESULT=$(xcrun notarytool submit "$STAGE/notarize.zip" --keychain-profile notary --wait --output-format json)
    if [ "$(printf '%s' "$RESULT" | plutil -extract status raw -o - -)" != Accepted ]; then
      printf '%s\n' "$RESULT" >&2
      xcrun notarytool log "$(printf '%s' "$RESULT" | plutil -extract id raw -o - -)" --keychain-profile notary >&2
      exit 1
    fi
    rm "$STAGE/notarize.zip"
    xcrun stapler staple "$APP"
  fi
  spctl --assess --type execute --verbose "$APP"
else
  SIGNATURE="ad-hoc"
fi

ditto "$APP" "$STAGE/Chip Pops.app"
find "$STAGE" -name .DS_Store -delete
xattr -cr "$STAGE"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE/Chip Pops.app" "$ZIP"

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Chip Pops.app"

echo "Built $ZIP, $SIGNATURE signed"
shasum -a 256 "$ZIP"
