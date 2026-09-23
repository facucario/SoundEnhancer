#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SoundEnhancer.app"
BIN="$ROOT/.build/release/SoundEnhancer"

echo "Building release executable..."
swift build -c release --package-path "$ROOT"

echo "Building driver..."
"$ROOT/Scripts/build-driver.sh"

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/SoundEnhancer"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/SoundEnhancerDriver.driver" "$APP/Contents/Resources/SoundEnhancerDriver.driver"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS="$ROOT/Scripts/SoundEnhancer.entitlements"
if [ "$IDENTITY" = "-" ]; then
    echo "Codesigning app (ad-hoc)..."
    codesign --force --sign - "$APP"
else
    echo "Codesigning app ($IDENTITY) with hardened runtime..."
    codesign --force --sign "$IDENTITY" --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" "$APP"
fi

echo "Done: $APP"
