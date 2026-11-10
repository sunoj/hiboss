#!/bin/bash
# Records media viewer verification commands, source HEAD and Xcode result bundles.
# Usage: media-tests.sh <output-base> [xcodebuild test filters/options]
# Dependencies: Xcode and the iPhone 18 Pro simulator type.
set -euo pipefail
OUT=$1
shift
cd "$(dirname "$0")/.."
# shellcheck source=ios/scripts/simulator.sh
source scripts/simulator.sh
simulator_command "iPhone 18 Pro"
COMMAND=("${SIMULATOR_COMMAND[@]}" xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID"
  -derivedDataPath /private/tmp/hiboss-media-viewer-dd
  -parallel-testing-enabled NO -collect-test-diagnostics never
  -resultBundlePath "$OUT.xcresult" "$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
