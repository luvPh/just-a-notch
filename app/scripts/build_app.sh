#!/usr/bin/env bash
# Builds JustANotch and assembles a runnable .app bundle (CLT, no Xcode needed).
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Just a Notch"
BUNDLE="$ROOT/build/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product JustANotch
BIN_PATH="$(swift build -c "$CONFIG" --product JustANotch --show-bin-path)"

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH/JustANotch" "$BUNDLE/Contents/MacOS/JustANotch"
cp "$ROOT/scripts/Info.plist" "$BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> Done: $BUNDLE"
echo "    Run with: open \"$BUNDLE\""
