#!/bin/bash
# Builds or tests the app and embedded share extension on the task's simulator.
# Records exact commands and source HEAD beside each log and test result bundle.
# Usage: share-tests.sh <output-base> <simulator-id> <build|test> [test filters/options]
set -euo pipefail
OUT=$1
SIM=$2
ACTION=$3
shift 3
cd "$(dirname "$0")/.."
COMMAND=(xcodebuild "$ACTION" -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /private/tmp/hiboss-box-share-dd
  CODE_SIGNING_ALLOWED=NO)
if [[ "$ACTION" == test ]]; then
  COMMAND+=(-parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$OUT.xcresult")
fi
COMMAND+=("$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
