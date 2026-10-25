#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SoundEnhancer.app"
DIST="$ROOT/dist"

: "${APPLE_ID:?APPLE_ID is required (your Apple ID email)}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required (your team ID)}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required (an app-specific password)}"

if [ ! -d "$APP" ]; then
    echo "Error: $APP not found. Run 'make app' first." >&2
    exit 1
fi

"$ROOT/Scripts/make-dmg.sh"

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
DMG="$DIST/SoundEnhancer-$VERSION.dmg"

echo "Submitting to Apple notary service..."
xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG"

echo "Done: $DMG"
