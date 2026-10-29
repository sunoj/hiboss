#!/bin/bash
# Runs one window-test command under the machine-wide lock, reusing evidence and capping runs.
# Exports: CLI `window-run.sh swift test --filter ...`; exit 75 when reuse or budget refuses.
# Dependencies: git, lockf, caffeinate, shasum; shared ledger in /private/tmp/hiboss-window-tests.
set -euo pipefail

state=${HIBOSS_WINDOW_STATE:-/private/tmp/hiboss-window-tests}
budget=${HIBOSS_WINDOW_BUDGET:-6}
hours=${HIBOSS_WINDOW_HOURS:-4}
ledger="$state/ledger.tsv"
lock=${HIBOSS_WINDOW_LOCK:-/private/tmp/hiboss-macos-window-tests.lock}
who=${AID_TASK_ID:-human/${USER:-unknown}}

[ $# -gt 0 ] || { printf 'usage: window-run.sh swift test --filter <classes>\n' >&2; exit 64; }
mkdir -p "$state"
touch "$ledger"

# Same sources, directory, command and test switches = same result; untracked inputs count.
source_key() {
    local root
    root=$(git rev-parse --show-toplevel)
    {
        git -C "$root" rev-parse HEAD:macos HEAD:HibossKit
        git -C "$root" diff HEAD -- macos HibossKit
        (cd "$root" && git ls-files -o --exclude-standard -z -- macos HibossKit \
            | xargs -0 shasum 2>/dev/null) || true
        printf '%s\n' "${PWD#"$root"}" "$*"
        # Test switches change what runs; per-run output paths and these runner knobs do not.
        env | grep '^HIBOSS_' | grep -v -E '^HIBOSS_(WINDOW_|PERF_OUTPUT=|PERF_COMMIT=)' | sort || true
    } | shasum -a 256 | cut -c1-16
}

# Prints the last ledger line for this key whose result column matches the awk test.
last_result() {
    awk -F '\t' -v key="$1" "\$2 == key && \$3 != \"start\" && ($2)" "$ledger" | tail -1
}

refuse() {
    printf 'window-run: %s\n' "$1" >&2
    exit 75
}

key=$(source_key "$@")
passed=$(last_result "$key" '$3 == 0')
failed=$(last_result "$key" '$3 != 0')
if [ -z "${HIBOSS_WINDOW_RERUN:-}" ]; then
    if [ -n "$passed" ]; then
        # Replay the log so callers that parse output see the same result.
        cat "$(cut -f5 <<<"$passed")" 2>/dev/null || true
        printf 'window-run: reused a passing run of these exact sources (log %s)\n' \
            "$(cut -f5 <<<"$passed")" >&2
        exit 0
    fi
    [ -z "$failed" ] || refuse "these exact sources already failed; read $(cut -f5 <<<"$failed").
Rerun only a known flaky test, with HIBOSS_WINDOW_RERUN=<reason>."
fi

since=$(($(date +%s) - hours * 3600))
used=$(awk -F '\t' -v since="$since" '$1 >= since && $3 == "start"' "$ledger" | wc -l | tr -d ' ')
if [ "$used" -ge "$budget" ] && [ -z "${HIBOSS_WINDOW_OVER_BUDGET:-}" ]; then
    awk -F '\t' -v since="$since" '$1 >= since && $3 == "start" { print $1 "\t" $4 "\t" $5 }' \
        "$ledger" | while IFS=$'\t' read -r started owner path; do
            printf '  %s  %s  %s\n' "$(date -r "$started" +%H:%M)" "$owner" "$path" >&2
        done
    refuse "machine budget spent: $used window runs in the last ${hours}h (limit $budget).
Reuse the logs above, or ask the human; HIBOSS_WINDOW_OVER_BUDGET=<reason> records an override."
fi

log="$state/$(date +%Y%m%d-%H%M%S)-$key.log"
reason="${HIBOSS_WINDOW_RERUN:-}${HIBOSS_WINDOW_OVER_BUDGET:+ over-budget: $HIBOSS_WINDOW_OVER_BUDGET}"
printf '%s\t%s\tstart\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$key" "$who" "$log" "$reason" "$*" \
    >> "$ledger"
printf 'window-run: run %s of %s in %sh; log %s\n' "$((used + 1))" "$budget" "$hours" "$log"
set +e
lockf -k "$lock" caffeinate -d -i -u "$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$key" "$code" "$who" "$log" "$reason" "$*" \
    >> "$ledger"
exit "$code"
