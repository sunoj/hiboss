#!/bin/bash
# Local iOS Settings verification with the exact source HEAD and command beside each result.
# Usage: scripts/settings-tests.sh <output-base> <simulator-name> [xcodebuild test filters/options]
# Writes <output-base>.log, .head, .command and .xcresult; uses the task's simulator DerivedData.
set -euo pipefail
OUT=$1
SIM=$2
shift 2
cd "$(dirname "$0")/.."
COMMAND=(xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss
  -destination "platform=iOS Simulator,name=$SIM"
  -derivedDataPath /private/tmp/hiboss-settings-v2-dd
  -parallel-testing-enabled NO -collect-test-diagnostics never
  -resultBundlePath "$OUT.xcresult" "$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
