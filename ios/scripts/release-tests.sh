#!/bin/bash
# Release gate (T5): every unit test plus the UI tests listed in release-ui-tests.txt.
# Refuses to run when a UI test class has no line in that list, so a new class is not left out.
# Usage: release-tests.sh <output-base>; today-tests.sh writes the log, xcresult, head and command.
set -euo pipefail
OUT=$1
cd "$(dirname "$0")/.."
LIST=scripts/release-ui-tests.txt
classes=$(grep -rhoE '^\s*(final )?class [A-Za-z0-9]+UITests\b' UITests | awk '{print $NF}' | sort -u)
listed=$(grep -vE '^\s*(#|$)' "$LIST" | awk '{print ($1 == "skip") ? $2 : $1}' | cut -d/ -f1 | sort -u)
missing=$(comm -23 <(echo "$classes") <(echo "$listed"))
if [[ -n $missing ]]; then
  echo "release-ui-tests.txt has no line for: ${missing//$'\n'/ }" >&2
  exit 2
fi
args=(-only-testing:HiBossTests)
while read -r id; do
  args+=("-only-testing:HiBossUITests/$id")
done < <(grep -vE '^\s*(#|$|skip )' "$LIST" | awk '{print $1}')
start=$(date +%s)
status=0
scripts/today-tests.sh "$OUT" "${args[@]}" || status=$?
echo "release gate: $(( $(date +%s) - start )) s, exit $status" | tee "$OUT.elapsed"
exit "$status"
