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
cp -R "$ROOT/SoundEnhancerDriver.driver" "$APP/Contents/Resources/SoundEnhancerDriver.driver"

echo "Codesigning (ad-hoc)..."
codesign --force --sign - "$APP"

echo "Done: $APP"
