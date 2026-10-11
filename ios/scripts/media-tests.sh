#!/bin/bash
# Records media viewer verification commands, source HEAD and Xcode result bundles.
# Usage: media-tests.sh <output-base> [xcodebuild test filters/options]
# Dependencies: Xcode and the designated iPhone 18 Pro simulator.
set -euo pipefail
OUT=$1
shift
cd "$(dirname "$0")/.."
COMMAND=(xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination 'platform=iOS Simulator,id=F3198616-B97E-4797-89A5-7BA26AD63B43'
  -derivedDataPath /private/tmp/hiboss-media-viewer-dd
  -parallel-testing-enabled NO -collect-test-diagnostics never
  -resultBundlePath "$OUT.xcresult" "$@")
git rev-parse HEAD > "$OUT.head"
printf '%q ' "${COMMAND[@]}" > "$OUT.command"
printf '\n' >> "$OUT.command"
"${COMMAND[@]}" > "$OUT.log" 2>&1
