#!/bin/bash
# Runs opt-in real-window CPU measurements through the shared window-run budget.
# Exports: Markdown table on stdout and a retained complete Swift test log.
# Dependencies: Swift and window-run.sh; release enables @testable imports explicitly.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
configuration=${1:-release}
case "$configuration" in release|debug) ;; *) echo 'usage: perf-survey.sh [release|debug]' >&2; exit 2 ;; esac
output=${HIBOSS_PERF_OUTPUT:-/private/tmp/hiboss-perf-survey-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$output"
export HIBOSS_PERF_OUTPUT="$output"
export HIBOSS_PERF_SURVEY=1
export HIBOSS_PERF_CONFIG="$configuration"
export HIBOSS_PERF_COMMIT
HIBOSS_PERF_COMMIT=$(git -C "$root" rev-parse HEAD)
if [ -n "$(git -C "$root" status --porcelain)" ]; then
    HIBOSS_PERF_COMMIT="$HIBOSS_PERF_COMMIT+dirty"
fi
printf 'Configuration: %s; commit: %s; log: %s\n' "$configuration" "$HIBOSS_PERF_COMMIT" "$output/run.log"
cd "$root/macos"
classes='MacosPerfSurveyTests|PerfSurveyIslandTests'
classes+='|PerfSurveySettingsTests|PerfSurveyHistoryTests'
scripts/window-run.sh \
    swift test -c "$configuration" -Xswiftc -enable-testing \
    --filter "HibossIslandTests\.($classes)/" \
    2>&1 | tee "$output/run.log"
if ! grep -q '^PERF ' "$output/run.log"; then
    echo 'No measurement rows were produced.' >&2
    exit 3
fi
printf '\n| Surface | Data | Content pt | Idle CPU %% | Update main CPU ms '
printf '| Interaction ms | Scroll ms | Build | Commit |\n'
printf '|---|---|---|---:|---:|---:|---:|---|---|\n'
sed -n 's/^PERF / /p' "$output/run.log" | tee "$output/rows.md"
