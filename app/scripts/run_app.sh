#!/usr/bin/env bash
# Build (debug) + (re)launch "Just a Notch". Used by the Stop hook to always
# re-run the app after Claude finishes editing. Exit 2 on build failure so the
# hook can re-wake Claude to fix it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Just a Notch"
BUNDLE="$ROOT/build/$APP_NAME.app"

# swift build resolves Package.swift from the current directory.
cd "$ROOT"

# Build debug bundle. Reuse build_app.sh's assembly logic.
if ! "$ROOT/scripts/build_app.sh" debug; then
  echo "BUILD FAILED" >&2
  exit 2
fi

# Kill any running instance, then relaunch fresh.
pkill -x JustANotch 2>/dev/null || true
# Chờ bản cũ thoát hẳn (mở ngay khi nó còn đang thoát → LaunchServices báo lỗi -600).
for _ in $(seq 1 30); do pgrep -x JustANotch >/dev/null || break; sleep 0.1; done
open "$BUNDLE" || { sleep 0.5; open "$BUNDLE"; }
echo "==> Relaunched $BUNDLE"
