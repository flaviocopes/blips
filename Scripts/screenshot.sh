#!/bin/sh
# Renders the main window from the real app views, with a library and one sound selected.
# It compiles BlipsCore into a static library, then the app's views with Scripts/screenshot.swift
# in place of the @main file, into an app with its own bundle ID, so it never touches Blips' settings.
# Usage: ./Scripts/screenshot.sh <library folder> [output folder, default: docs] [sound ID, default: success-002]
# Set BUILD_ONLY=1 to build the capture app without running it, to run it on another Mac.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
LIBRARY="$1"
OUTPUT="${2:-docs}"
SOUND="${3:-success-002}"
BUILD="$ROOT/.build/screenshot"
APP="$BUILD/Blips Screenshot.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  TARGET="$arch-apple-macos14.0"
  swiftc -O -swift-version 6 -parse-as-library -target "$TARGET" -module-name BlipsCore \
    -emit-library -static -emit-module -emit-module-path "$BUILD/$arch/BlipsCore.swiftmodule" \
    -o "$BUILD/$arch/libBlipsCore.a" Sources/BlipsCore/*.swift
  find Sources/BlipsApp -name '*.swift' ! -exec grep -q '^@main' {} \; -exec \
    swiftc -O -swift-version 6 -parse-as-library -target "$TARGET" -I "$BUILD/$arch" -L "$BUILD/$arch" -lBlipsCore \
    -o "$BUILD/Screenshot-$arch" Scripts/screenshot.swift {} +
done
lipo -create "$BUILD/Screenshot-arm64" "$BUILD/Screenshot-x86_64" -output "$APP/Contents/MacOS/Screenshot"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Screenshot</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.blips.screenshot</string>
  <key>CFBundleName</key>
  <string>Blips</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

if [ "${BUILD_ONLY:-}" = 1 ]; then
  echo "$APP"
  exit 0
fi

mkdir -p "$OUTPUT"
OUTPUT=$(CDPATH= cd -- "$OUTPUT" && pwd)
LIBRARY=$(CDPATH= cd -- "$LIBRARY" && pwd)
open -n "$APP" --args "$OUTPUT" "$LIBRARY" "$SOUND" -AppleLocale en_US -AppleLanguages '(en)'
sleep 1
while pgrep -f "Blips Screenshot.app/Contents/MacOS" >/dev/null; do sleep 1; done
ls "$OUTPUT"
