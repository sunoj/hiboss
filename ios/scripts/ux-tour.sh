#!/bin/bash
# Screenshot tour of the demo app for UX review (light + dark, en + zh-Hans, empty, XXL text).
# Usage: scripts/ux-tour.sh <output-dir> [simulator-name]   (run from ios/)
# Writes <output-dir>/shots/<appearance><variant>-<nn>-<surface>.png and a 900px copy in small/.
set -euo pipefail
OUT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); SIM=${2:-iPhone 17}
mkdir -p "$OUT"; rm -rf "$OUT"/*.xcresult "$OUT/shots"
xcodegen generate -q
xcrun simctl boot "$SIM" 2>/dev/null || true
run() { # $1 appearance, $2 prefix, $3.. -only-testing filters
  local appearance=$1 prefix=$2; shift 2
  xcrun simctl ui "$SIM" appearance "$appearance"
  TEST_RUNNER_UX_TOUR_PREFIX="$prefix" xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss \
    -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$OUT/dd" \
    -resultBundlePath "$OUT/$appearance.xcresult" "$@" 2>&1 | grep -E 'error:|TEST (SUCCEEDED|FAILED)|Test Case .*failed' || true
}
run light "" -only-testing:HiBossUITests/UXTourUITests
run dark "dark-" -only-testing:HiBossUITests/UXTourUITests/testTourChinese
xcrun simctl ui "$SIM" appearance light
mkdir -p "$OUT/shots/raw" "$OUT/shots/small"
for bundle in "$OUT"/*.xcresult; do
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$OUT/shots/raw" >/dev/null
  python3 - "$OUT/shots/raw" <<'PY'
import json, os, shutil, sys
raw = sys.argv[1]
for test in json.load(open(os.path.join(raw, 'manifest.json'))):
    for item in test.get('attachments', []):
        name = (item.get('suggestedHumanReadableName') or item['exportedFileName']).split('_0_')[0]
        shutil.copy(os.path.join(raw, item['exportedFileName']), os.path.join(raw, '..', name.removesuffix('.png') + '.png'))
PY
  rm -f "$OUT/shots/raw/manifest.json"
done
for f in "$OUT"/shots/*.png; do sips -Z 900 "$f" --out "$OUT/shots/small/$(basename "$f")" >/dev/null; done
ls "$OUT/shots/small" | wc -l | xargs echo "screenshots:"
