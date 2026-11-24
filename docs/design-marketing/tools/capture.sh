#!/bin/bash
# Capture real HiBoss screens from the iOS demo mode on one simulator; nothing is drawn or retouched.
# Usage: capture.sh <simulator-udid> <HiBoss.app> <output-dir> [scene ...]
# Writes <output-dir>/<scene>-<lang>-<appearance>.png at the device's native pixel size.
# The simulator must already be booted and owned by the caller (for example a simbox lease).
set -euo pipefail
SIM=$1; APP=$2; OUT=$3; shift 3
mkdir -p "$OUT"
SCENES=("$@")
[[ ${#SCENES[@]} -gt 0 ]] || SCENES=(today decision session sessions box progress allclear)
LANGS=${CAPTURE_LANGS:-en zh}
APPEARANCES=${CAPTURE_APPEARANCES:-light dark}
SETTLE=${CAPTURE_SETTLE:-7}

flags() { # scene -> SIMCTL_CHILD_* assignments, one per line
  echo HIBOSS_DEMO=1; echo HIBOSS_DEMO_STABLE_DEADLINES=1; echo HIBOSS_DEMO_OPTION_MEDIA=1
  case $1 in
    today) ;;
    session) echo HIBOSS_DEMO_SESSION=1 ;;
    sessions) echo HIBOSS_TAB=sessions ;;
    box) echo HIBOSS_TAB=box ;;
    progress) echo HIBOSS_TAB=progress ;;
    allclear) echo HIBOSS_DEMO_EMPTY=1 ;;
    decision) echo HIBOSS_DEMO_OPEN=c1 ;;
    *) echo "unknown scene: $1" >&2; return 1 ;;
  esac
}

xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3
for appearance in $APPEARANCES; do
  xcrun simctl ui "$SIM" appearance "$appearance"
  for lang in $LANGS; do
    if [[ $lang == zh ]]; then locale=(-AppleLanguages "(zh-Hans)" -AppleLocale zh_CN)
    else locale=(-AppleLanguages "(en)" -AppleLocale en_US); fi
    for scene in "${SCENES[@]}"; do
      xcrun simctl terminate "$SIM" ai.hiboss.app >/dev/null 2>&1 || true
      env_args=()
      while read -r pair; do env_args+=("SIMCTL_CHILD_$pair"); done < <(flags "$scene")
      env "${env_args[@]}" xcrun simctl launch "$SIM" ai.hiboss.app "${locale[@]}" >/dev/null
      python3 -c "import time, sys; time.sleep(float(sys.argv[1]))" "$SETTLE"
      xcrun simctl io "$SIM" screenshot "$OUT/$scene-$lang-$appearance.png" >/dev/null 2>&1
      echo "$scene-$lang-$appearance.png"
    done
  done
done
xcrun simctl terminate "$SIM" ai.hiboss.app >/dev/null 2>&1 || true
xcrun simctl ui "$SIM" appearance light
xcrun simctl status_bar "$SIM" clear
