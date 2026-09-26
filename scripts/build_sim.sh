#!/bin/zsh
# DEMO ONLY. Local build check outside Bitrig. Bitrig remains the real build and demo host.
# Usage: scripts/build_sim.sh [screenshot.png] [launch-args...]
# Generates build/Generalizable.xcodeproj from Project.json, builds for an iPhone simulator,
# installs, launches, and optionally saves a screenshot. Exit code != 0 on build failure.
set -euo pipefail
cd "${0:A:h}/.."
DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
m=[x['udid'] for k,v in d.items() for x in v if x['name']==sys.argv[1]]
print(m[0])" "$DEVICE")
xcodegen --spec Project.json -q
xcodebuild -project Generalizable.xcodeproj -scheme Generalizable \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/dd -quiet GENERATE_INFOPLIST_FILE=YES build 2>&1 \
  | grep -E "error:|warning: unre|BUILD FAILED" || true
APP=build/dd/Build/Products/Debug-iphonesimulator/Generalizable.app
[[ -d $APP ]] || { echo "BUILD FAILED"; exit 1; }
echo "BUILD OK ($DEVICE $UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
shift_args=("${@:2}")
xcrun simctl launch "$UDID" "$BID" "${shift_args[@]}" >/dev/null
if [[ -n "${1:-}" ]]; then
  sleep "${SHOT_DELAY:-4}"
  xcrun simctl io "$UDID" screenshot "$1" >/dev/null && echo "SCREENSHOT $1"
fi
