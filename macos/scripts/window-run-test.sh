#!/bin/bash
# Exercises window-run.sh reuse, failure and budget rules with stubbed lockf and caffeinate.
# Exports: hermetic shell self-test; prints the number of passing checks.
# Dependencies: window-run.sh and the surrounding git checkout; runs no Swift and opens no window.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/window-run.sh"
temp=$(mktemp -d "${TMPDIR:-/private/tmp}/hiboss-window-run-test.XXXXXX")
trap 'rm -r "$temp"' EXIT
mkdir "$temp/bin"
# lockf -k <file> caffeinate ... and caffeinate -d -i -u <command>: count, then run the command.
printf '#!/bin/bash\nshift 2\nexec "$@"\n' > "$temp/bin/lockf"
printf '#!/bin/bash\nshift 3\necho run >> "%s/runs"\nexec "$@"\n' "$temp" > "$temp/bin/caffeinate"
chmod +x "$temp/bin/lockf" "$temp/bin/caffeinate"
export PATH="$temp/bin:$PATH" HIBOSS_WINDOW_STATE="$temp/state" HIBOSS_WINDOW_LOCK="$temp/lock"
unset HIBOSS_WINDOW_RERUN HIBOSS_WINDOW_OVER_BUDGET AID_TASK_ID
checks=0

runs() { [ -f "$temp/runs" ] && wc -l < "$temp/runs" | tr -d ' ' || echo 0; }
expect() { # expect <exit> <runs> <label> -- command...
    local want=$1 count=$2 label=$3 got=0
    shift 4
    "$script" "$@" > "$temp/out" 2>&1 || got=$?
    [ "$got" = "$want" ] || { cat "$temp/out"; echo "FAIL $label: exit $got, want $want"; exit 1; }
    [ "$(runs)" = "$count" ] || { cat "$temp/out"; echo "FAIL $label: runs $(runs), want $count"; exit 1; }
    checks=$((checks + 1))
}

export HIBOSS_WINDOW_BUDGET=3
expect 0 1 'first pass runs' -- true
expect 0 1 'identical pass is reused' -- true
expect 1 2 'new command runs and fails' -- false
expect 75 2 'identical failure is refused' -- false
HIBOSS_WINDOW_RERUN='flaky check' expect 1 3 'named rerun runs' -- false
expect 75 3 'budget refuses a fourth run' -- sh -c 'exit 0'
HIBOSS_WINDOW_OVER_BUDGET='human approved' expect 0 4 'override runs' -- sh -c 'exit 0'
grep -q 'over-budget: human approved' "$temp/state/ledger.tsv" || { echo 'FAIL override not recorded'; exit 1; }
checks=$((checks + 1))
HIBOSS_WINDOW_BUDGET=1 expect 0 4 'reuse costs no budget' -- true
HIBOSS_PERF_FILTER=a HIBOSS_WINDOW_BUDGET=9 expect 0 5 'a different test switch runs' -- true
HIBOSS_PERF_FILTER=a HIBOSS_PERF_OUTPUT=/x HIBOSS_WINDOW_BUDGET=9 expect 0 5 'output path is ignored' -- true
HIBOSS_WINDOW_BUDGET=9 expect 0 6 'replayed run prints its log' -- echo replay-marker
HIBOSS_WINDOW_BUDGET=9 expect 0 6 'second call replays' -- echo replay-marker
grep -q replay-marker "$temp/out" || { echo 'FAIL reuse did not replay the log'; exit 1; }
checks=$((checks + 1))
echo "window-run self-test: $checks checks passed"
