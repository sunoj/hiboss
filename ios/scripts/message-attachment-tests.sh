#!/bin/bash
# Records local attachment verification commands, source HEAD and Xcode result bundles.
# Usage: message-attachment-tests.sh <output-base> <build|test> [xcodebuild options]
# Dependencies: Xcode and the dedicated HiBoss-Message-Attachments simulator.
set -euo pipefail
OUT=$1
ACTION=$2
shift 2
cd "$(dirname "$0")/.."
COMMAND=(xcodebuild "$ACTION" -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination 'platform=iOS Simulator,name=HiBoss-Message-Attachments'
  -derivedDataPath /private/tmp/hiboss-message-attachments-dd
  -parallel-testing-enabled NO -collect-test-diagnostics never
  -resultBundlePath "$OUT.xcresult" "$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
