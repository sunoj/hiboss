#!/bin/bash
# Runs focused Box verification with isolated DerivedData on the supplied simulator.
# Records the source HEAD and exact command beside each log and test result bundle.
# Usage: box-tests.sh <output-base> <simulator-id> <build|test> [test filters/options]
set -euo pipefail
OUT=$1
SIM=$2
ACTION=$3
shift 3
cd "$(dirname "$0")/.."
COMMAND=(xcodebuild "$ACTION" -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination "platform=iOS Simulator,id=$SIM"
  -derivedDataPath /private/tmp/hiboss-box-provenance-dd CODE_SIGNING_ALLOWED=NO)
if [[ "$ACTION" == test ]]; then
  COMMAND+=(-parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$OUT.xcresult")
fi
COMMAND+=("$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
