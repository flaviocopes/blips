#!/bin/sh
# Builds a universal (Apple silicon and Intel) dist/Chip Pops.app, with the blips command
# at Contents/Helpers/blips and the agent skill at Contents/Resources/SKILL.md.
# Signs with Flavio's Developer ID when the certificate is in the keychain, and ad-hoc everywhere else (CI, forks).
# Both binaries get the allow-jit entitlement: without it, JavaScriptCore runs jsfxr in its interpreter, 8 times slower.
# The version comes from Blips.version in Sources/BlipsCore/Version.swift.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/Chip Pops.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"

cd "$ROOT"
VERSION=$(sed -n 's/^ *public static let version = "\(.*\)"$/\1/p' Sources/BlipsCore/Version.swift)
swift build -c release --arch arm64 --arch x86_64 --product BlipsApp
swift build -c release --arch arm64 --arch x86_64 --product blips

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES" "$CONTENTS/Helpers"
cp ".build/apple/Products/Release/BlipsApp" "$MACOS/Chip Pops"
cp ".build/apple/Products/Release/blips" "$CONTENTS/Helpers/blips"
cp skill/blips/SKILL.md "$RESOURCES/SKILL.md"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Chip Pops</string>
  <key>CFBundleExecutable</key>
  <string>Chip Pops</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.blips</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Chip Pops</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

ENTITLEMENTS="$ROOT/Scripts/Blips.entitlements"
IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
  SIGNATURE="Developer ID"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$CONTENTS/Helpers/blips"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$MACOS/Chip Pops"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
else
  SIGNATURE="ad-hoc"
  codesign --force --entitlements "$ENTITLEMENTS" --sign - "$CONTENTS/Helpers/blips"
  codesign --force --entitlements "$ENTITLEMENTS" --sign - "$MACOS/Chip Pops"
  codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "Built $APP $VERSION for $(lipo -archs "$MACOS/Chip Pops"), $SIGNATURE signed"
echo "$APP"
