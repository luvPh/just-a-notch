#!/usr/bin/env bash
# Sinh Resources/AppIcon.icns từ make_icon.swift. Chạy lại khi đổi thiết kế icon:
#   scripts/make_icns.sh [kitty|aurora|graphite]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-kitty}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swift "$ROOT/scripts/make_icon.swift" "$VARIANT" "$TMP/1024.png" >/dev/null
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
echo "==> Wrote $ROOT/Resources/AppIcon.icns ($VARIANT)"
