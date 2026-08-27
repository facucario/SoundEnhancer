#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Driver/SoundEnhancerDriver.c"
PLIST="$ROOT/Driver/Info.plist"
BUNDLE="$ROOT/SoundEnhancerDriver.driver"
BIN="$BUNDLE/Contents/MacOS/SoundEnhancerDriver"

SDKROOT="$(xcrun --show-sdk-path)"

echo "Building driver bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"

clang -bundle \
    -isysroot "$SDKROOT" \
    -mmacosx-version-min=10.10 \
    -arch arm64 -arch x86_64 \
    -fblocks \
    -framework CoreFoundation \
    -framework CoreAudio \
    -framework IOKit \
    -framework Accelerate \
    -o "$BIN" \
    "$SRC"

cp "$PLIST" "$BUNDLE/Contents/Info.plist"

echo "Codesigning driver (ad-hoc)..."
codesign --force --sign - "$BUNDLE"

echo "Done: $BUNDLE"
