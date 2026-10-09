#!/usr/bin/env bash
# Cài Just a Notch: curl -fsSL https://raw.githubusercontent.com/luvPh/just-a-notch/main/install.sh | bash
set -euo pipefail
REPO="luvPh/just-a-notch"
APP="Just a Notch.app"
URL="https://github.com/$REPO/releases/latest/download/JustANotch.zip"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "==> Tải $URL"
curl -fL --progress-bar "$URL" -o "$TMP/JustANotch.zip"
ditto -x -k "$TMP/JustANotch.zip" "$TMP"

DEST="/Applications"; [ -w "$DEST" ] || DEST="$HOME/Applications"; mkdir -p "$DEST"
osascript -e 'quit app "Just a Notch"' >/dev/null 2>&1 || true
rm -rf "$DEST/$APP"
ditto "$TMP/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "==> Đã cài vào $DEST/$APP"
open "$DEST/$APP"
