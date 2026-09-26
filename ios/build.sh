#!/bin/zsh
# Usage: ./build.sh — builds Generalizable for the iOS Simulator (iPhone Duo needs Xcode 27.1).
# One shared derived-data dir + a lock so parallel agents never run two builds at once
# (ten separate caches filled the disk on 2026-09-26).
set -e
cd "$(dirname "$0")"
LOCK=/tmp/gz-build.lock
until mkdir "$LOCK" 2>/dev/null; do sleep 3; done
trap 'rmdir "$LOCK"' EXIT
xcodegen generate --quiet
xcodebuild -project Generalizable.xcodeproj -scheme Generalizable -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/gz-dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -60
