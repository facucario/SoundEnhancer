#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SoundEnhancer.app"
DIST="$ROOT/dist"
STAGING_ZIP="$DIST/SoundEnhancer-notarize.zip"

: "${APPLE_ID:?APPLE_ID is required (your Apple ID email)}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required (your team ID)}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required (an app-specific password)}"

if [ ! -d "$APP" ]; then
    echo "Error: $APP not found. Run 'make app' first." >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
mkdir -p "$DIST"
rm -f "$STAGING_ZIP"

echo "Zipping app for notarization..."
ditto -c -k --keepParent "$APP" "$STAGING_ZIP"

echo "Submitting to Apple notary service..."
xcrun notarytool submit "$STAGING_ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"

rm -f "$STAGING_ZIP"
echo "Packaging final zip..."
ditto -c -k --keepParent "$APP" "$DIST/SoundEnhancer-$VERSION.zip"

echo "Done: $DIST/SoundEnhancer-$VERSION.zip"
