#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SoundEnhancer.app"
BIN="$ROOT/.build/release/SoundEnhancer"

echo "Building release executable..."
swift build -c release --package-path "$ROOT"

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/SoundEnhancer"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "Codesigning (ad-hoc)..."
codesign --force --sign - "$APP"

echo "Done: $APP"
