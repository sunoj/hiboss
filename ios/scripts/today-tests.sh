#!/bin/bash
# Runs Today tests on the assigned iPhone 17 with isolated build output.
# Records HEAD and command beside the log and xcresult for focused and full runs.
# Usage: today-tests.sh <output-base> [xcodebuild test filters/options]
set -euo pipefail
OUT=$1
shift
cd "$(dirname "$0")/.."
COMMAND=(xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination 'platform=iOS Simulator,name=iPhone 17'
  -derivedDataPath /private/tmp/hiboss-today-settle-dd CODE_SIGNING_ALLOWED=NO
  -parallel-testing-enabled NO -collect-test-diagnostics never
  -resultBundlePath "$OUT.xcresult" "$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
