#!/bin/bash
# Captures held and escalated states in eight appearance/language/text-size combinations.
# Usage: scripts/intermediate-states.sh <results-dir> <simulator-uuid> <derived-data> [--supplement] [variants...]
# Dependencies: a built test bundle, xcrun, Python 3 and export-intermediate-shots.py.
set -euo pipefail
RESULTS=$1
SIMULATOR=$2
DERIVED=$3
shift 3
mkdir -p "$RESULTS"
TESTS=(
  -only-testing:HiBossUITests/IntermediateBehaviorUITests/testRefreshKeepsHomeAndListContent
  -only-testing:HiBossUITests/IntermediateBehaviorUITests/testTypedReplyKeepsDraftAfterFailure
)
if [ "${1:-}" = "--supplement" ]; then
  TESTS+=(
    -only-testing:HiBossUITests/IntermediateStateUITests/testHomeCoverage
    -only-testing:HiBossUITests/IntermediateStateUITests/testHomePartialAndConnection
    -only-testing:HiBossUITests/IntermediatePanelUITests
    -only-testing:HiBossUITests/IntermediateMediaUITests/testProgressImagesAndLikes
    -only-testing:HiBossUITests/IntermediateOnboardingUITests/testOwnedNotificationRegistration
    -only-testing:HiBossUITests/IntermediateOnboardingUITests/testOwnedPreferencesAndCamera
  )
  shift
else
  TESTS+=(
    -only-testing:HiBossUITests/IntermediateStateUITests
    -only-testing:HiBossUITests/IntermediateMediaUITests
    -only-testing:HiBossUITests/IntermediatePanelUITests
    -only-testing:HiBossUITests/IntermediateOnboardingUITests
  )
fi
if [ "$#" -eq 0 ]; then
  set -- en-light en-dark zh-light zh-dark en-ax-light en-ax-dark zh-ax-light zh-ax-dark
fi
for variant in "$@"; do
  appearance=${variant##*-}
  xcrun simctl ui "$SIMULATOR" appearance "$appearance"
  TEST_RUNNER_INTERMEDIATE_VARIANT="$variant" xcodebuild test-without-building \
    -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR" -derivedDataPath "$DERIVED" \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -resultBundlePath "$RESULTS/$variant.xcresult" \
    "${TESTS[@]}" \
    >"$RESULTS/$variant.log" 2>&1
  python3 scripts/export-intermediate-shots.py "$RESULTS/$variant.xcresult" \
    "Screenshots/intermediate/after/$variant"
done
xcrun simctl ui "$SIMULATOR" appearance light
