#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SoundEnhancer.app"
DIST="$ROOT/dist"

if [ ! -d "$APP" ]; then
    echo "Error: $APP not found. Run 'make app' first." >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
DMG="$DIST/SoundEnhancer-$VERSION.dmg"
STAGING="$DIST/SoundEnhancer-$VERSION"

mkdir -p "$DIST"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating DMG..."
hdiutil create \
    -volname "SoundEnhancer" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"

rm -rf "$STAGING"
echo "Done: $DMG"
