#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -n "${VERSION_OVERRIDE:-}" ]; then
    echo "$VERSION_OVERRIDE"
    exit 0
fi

VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi
if [ -z "$VERSION" ]; then
    VERSION="0.0.0"
fi

echo "${VERSION#v}"
