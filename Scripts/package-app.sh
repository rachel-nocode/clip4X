#!/usr/bin/env bash
set -euo pipefail

# Build, sign (Developer ID + hardened runtime), package a DMG,
# notarize it via the stored notarytool keychain profile, and staple.
#
# Override defaults with env vars:
#   DEV_ID          codesign identity (Developer ID Application)
#   NOTARY_PROFILE  xcrun notarytool --keychain-profile name
#   SKIP_NOTARIZE=1 sign only, do not notarize/staple

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/Build/Clip4X.app"
STAGING="$ROOT/Build/dmg-staging"
BINARY="$ROOT/.build/release/Clip4X"
ICON="$ROOT/Assets/AppIcon/Clip4X.icns"
VERSION="0.1.0"
DMG="$ROOT/Build/Clip4X-$VERSION.dmg"

DEV_ID="${DEV_ID:-Developer ID Application: Rachel Larralde (5U92RP4C5J)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarize}"

cd "$ROOT"
swift build -c release

# --- assemble .app bundle ---
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/Clip4X"
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP_DIR/Contents/Resources/Clip4X.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Clip4X</string>
    <key>CFBundleIdentifier</key>
    <string>audio.witch.clip4x</string>
    <key>CFBundleName</key>
    <string>Clip4X</string>
    <key>CFBundleDisplayName</key>
    <string>Clip4X</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>Clip4X</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# --- code sign with hardened runtime (required for notarization) ---
codesign --force --options runtime --timestamp \
  --sign "$DEV_ID" "$APP_DIR/Contents/MacOS/Clip4X"
codesign --force --options runtime --timestamp \
  --sign "$DEV_ID" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

# --- build DMG ---
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/Clip4X.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Clip4X" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$DEV_ID" "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "Signed (notarization skipped): $DMG"
  exit 0
fi

# --- notarize + staple ---
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "Notarized DMG: $DMG"
