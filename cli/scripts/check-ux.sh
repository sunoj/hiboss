#!/bin/sh
# Runs the full CLI tests and displays help/recovery behavior using synthetic config.
# Outputs: test log path, test output, help and diagnostics with exit statuses.
# Dependencies: Cargo, optional aid, and a Linux remote build host via rbox.
set -eu
cd "$(dirname "$0")/.."
ux_test_log=$(mktemp)
ux_test_status=0
if command -v aid >/dev/null 2>&1; then
    aid test >"$ux_test_log" 2>&1 || ux_test_status=$?
else
    cargo test >"$ux_test_log" 2>&1 || ux_test_status=$?
fi
printf 'CLI test log: %s\n' "$ux_test_log"
cat "$ux_test_log"
[ "$ux_test_status" -eq 0 ] || exit "$ux_test_status"
ux_binary="${CARGO_TARGET_DIR:-target}/debug/hiboss"
ux_sandbox_root=$(mktemp -d)
trap 'rm -rf "$ux_sandbox_root"' EXIT
run() {
    env -i HOME="$ux_sandbox_root" XDG_CONFIG_HOME="$ux_sandbox_root/.config" \
        PATH="$PATH" NO_COLOR=1 "$ux_binary" "$@"
}
run --help
ux_probe_status=0
run || ux_probe_status=$?
printf 'Bare invocation exit=%s\n' "$ux_probe_status"
ux_probe_status=0
run send hi || ux_probe_status=$?
printf 'Missing config exit=%s\n' "$ux_probe_status"
mkdir -p "$ux_sandbox_root/.config/hiboss"
printf '{"server":' > "$ux_sandbox_root/.config/hiboss/config.json"
ux_probe_status=0
run send hi || ux_probe_status=$?
printf 'Malformed config exit=%s\n' "$ux_probe_status"
