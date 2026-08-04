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
# Sign with a stable self-signed identity so the code signature (and thus its
# TCC designated requirement) stays constant across rebuilds — otherwise macOS
# revokes Full Disk Access every build and the Notifications feature can't read
# the notification DB. Override the identity with CODESIGN_IDENTITY if needed;
# falls back to ad-hoc (FDA will reset each build) when the cert isn't present.
SIGN_ID="${CODESIGN_IDENTITY:-Just a Notch Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "==> Signing with \"$SIGN_ID\" (stable → Full Disk Access persists)"
  codesign --force --sign "$SIGN_ID" "$BUNDLE" >/dev/null 2>&1 || echo "   (codesign failed)"
else
  echo "==> \"$SIGN_ID\" not found — ad-hoc signing (Full Disk Access resets each build)"
  codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "   (codesign skipped)"
fi

echo "==> Done: $BUNDLE"
echo "    Run with: open \"$BUNDLE\""
