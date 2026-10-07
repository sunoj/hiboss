#!/bin/bash
# Screenshot tour of Home, Activity, Progress and Settings (light/dark, en/zh, accessibility L).
# Usage: scripts/ux-tour.sh <output-dir> [simulator-name]   (run from ios/)
# Writes <output-dir>/shots/<appearance><variant>-<nn>-<surface>.png and a 900px copy in small/.
# SETTINGS_ONLY=1 captures Settings; SETTINGS_DELIVERY_ONLY=1 captures Delivery details in the same matrix.
set -euo pipefail
OUT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); SIM=${2:-iPhone 17}
mkdir -p "$OUT"; rm -rf "$OUT"/*.xcresult "$OUT/shots"
if ! xcrun simctl list devices booted | grep -F "$SIM (" >/dev/null; then
  xcrun simctl boot "$SIM"
fi
run() { # $1 appearance, $2 prefix, $3.. -only-testing filters
  local appearance=$1 prefix=$2; shift 2
  xcrun simctl ui "$SIM" appearance "$appearance"
  TEST_RUNNER_UX_TOUR_DELIVERY_ONLY="${SETTINGS_DELIVERY_ONLY:-0}" \
    TEST_RUNNER_UX_TOUR_PREFIX="$prefix" xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss \
    -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$OUT/dd" \
    -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$OUT/$appearance.xcresult" "$@" \
    >"$OUT/$appearance.log" 2>&1 || {
      tail -n 80 "$OUT/$appearance.log" >&2
      return 1
    }
}
if [[ ${SETTINGS_ONLY:-0} == 1 || ${SETTINGS_DELIVERY_ONLY:-0} == 1 ]]; then
  FILTERS=(-only-testing:HiBossUITests/SettingsTourUITests)
else
  FILTERS=(-only-testing:HiBossUITests/UXTourUITests -only-testing:HiBossUITests/UXSurfaceUITests
    -only-testing:HiBossUITests/SettingsTourUITests -only-testing:HiBossUITests/ActivityNavigationUITests
    -skip-testing:HiBossUITests/UXTourUITests/testTourLanguage)
fi
run light "" "${FILTERS[@]}"
mv "$OUT/light.xcresult" "$OUT/base-light.xcresult"
run dark "dark-" "${FILTERS[@]}"
# Extra languages: TOUR_LANGS="ar th hi" scripts/ux-tour.sh <dir>
for lang in ${TOUR_LANGS:-}; do
  TEST_RUNNER_UX_TOUR_LANG="$lang" run light "" -only-testing:HiBossUITests/UXTourUITests/testTourLanguage
  mv "$OUT/light.xcresult" "$OUT/lang-$lang.xcresult"
done
xcrun simctl ui "$SIM" appearance light
mkdir -p "$OUT/shots/raw" "$OUT/shots/small"
for bundle in "$OUT"/*.xcresult; do
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$OUT/shots/raw" >/dev/null
  python3 - "$OUT/shots/raw" <<'PY'
import json, os, shutil, sys
raw = sys.argv[1]
for test in json.load(open(os.path.join(raw, 'manifest.json'))):
    for item in test.get('attachments', []):
        if not item['exportedFileName'].endswith('.png'):
            continue
        name = (item.get('suggestedHumanReadableName') or item['exportedFileName']).split('_0_')[0]
        shutil.copy(os.path.join(raw, item['exportedFileName']), os.path.join(raw, '..', name.removesuffix('.png') + '.png'))
PY
  rm -f "$OUT/shots/raw/manifest.json"
done
for f in "$OUT"/shots/*.png; do sips -Z 900 "$f" --out "$OUT/shots/small/$(basename "$f")" >/dev/null; done
ls "$OUT/shots/small" | wc -l | xargs echo "screenshots:"
