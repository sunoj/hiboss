#!/bin/bash
# T3 verification for session threads and the message body surfaces sharing reaction chips.
# Usage: scripts/thread-tests.sh <output-directory> <simulator-id>; records HEAD and tee logs.
set -euo pipefail
OUT=$1
SIM=$2
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
git rev-parse HEAD > "$OUT/head.txt"
BASE=(xcodebuild -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /private/tmp/hiboss-threads-dd)
printf '%q ' "${BASE[@]}" build > "$OUT/build-command.txt"
"${BASE[@]}" build 2>&1 | tee "$OUT/build.log"
TEST=("${BASE[@]}" -parallel-testing-enabled NO -collect-test-diagnostics never
  -resultBundlePath "$OUT/tests.xcresult" -only-testing:HiBossTests
  -only-testing:HiBossUITests/SessionThreadsUITests
  -only-testing:HiBossUITests/SessionBubblesUITests
  -only-testing:HiBossUITests/SessionPageLayoutUITests
  -only-testing:HiBossUITests/SessionsV4UITests
  -only-testing:HiBossUITests/ActivityNavigationUITests
  -only-testing:HiBossUITests/MessageAttachmentUITests
  -only-testing:HiBossUITests/OptionMediaUITests
  -only-testing:HiBossUITests/MessageMarkdownUITests
  -only-testing:HiBossUITests/HomeDecisionDetailUITests
  -only-testing:HiBossUITests/SessionUnreadUITests test)
printf '%q ' "${TEST[@]}" > "$OUT/test-command.txt"
"${TEST[@]}" 2>&1 | tee "$OUT/tests.log"
