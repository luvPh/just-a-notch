#!/usr/bin/env bash
# Builds NotchIsland via SwiftPM and assembles a runnable .app bundle.
# Works with Command Line Tools (no full Xcode required).
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Notch Island"
BUNDLE="$ROOT/build/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
# Build only the app product; the check runner is a debug-only tool.
swift build -c "$CONFIG" --product NotchIsland

BIN_PATH="$(swift build -c "$CONFIG" --product NotchIsland --show-bin-path)"

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH/NotchIsland" "$BUNDLE/Contents/MacOS/NotchIsland"
cp "$ROOT/scripts/Info.plist" "$BUNDLE/Contents/Info.plist"

# Ad-hoc sign so macOS will run it locally.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || \
  echo "   (codesign skipped/failed — app will still run locally)"

echo "==> Done: $BUNDLE"
echo "    Run with: open \"$BUNDLE\""
