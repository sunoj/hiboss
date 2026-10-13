#!/bin/bash
# Exercises verification planning against the real repository without executing Swift.
# Exports: hermetic shell self-test and assertion totals.
# Dependencies: verify-tier.sh, macOS grep/git, and a stub Python audit runner.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
script="$script_dir/verify-tier.sh"
root=$(cd "$script_dir/../.." && pwd)
temp=$(mktemp -d "${TMPDIR:-/private/tmp}/hiboss-verify-tier-test.XXXXXX")
trap 'rm -r "$temp"' EXIT
checks=0
cases=0
output=

fail() {
    printf 'FAIL: %s\n%s\n' "$1" "$output" >&2
    exit 1
}

contains() {
    printf '%s\n' "$output" | grep -F -q -- "$1" || fail "missing: $1"
    checks=$((checks + 1))
}

excludes() {
    if printf '%s\n' "$output" | grep -F -q -- "$1"; then fail "unexpected: $1"; fi
    checks=$((checks + 1))
}

plan() {
    output=$("$script" --files "$@")
    cases=$((cases + 1))
}

assert_rejected() {
    if output=$("$script" "$@" 2>&1); then fail "arguments accepted: $*"; fi
    cases=$((cases + 1))
    contains 'usage:'
}

check_docs_and_strings() {
    plan docs/macos-design-v2.md README.md
    contains 'tier: M0'
    contains 'logic classes: none'
    contains 'window classes: none'
    contains 'python3 macos/scripts/i18n-audit.py'
    excludes 'swift'
    plan macos/Sources/HibossIsland/Resources/Localizable.xcstrings
    contains 'tier: M0'
    excludes 'swift'
    plan HibossKit/README.md server/src/index.ts
    contains 'tier: M0'
    excludes 'swift'
}

check_focused_classes() {
    plan Sources/HibossIsland/Formatting/SharedTimestamp.swift
    contains 'tier: M1'
    contains 'logic classes: SharedFormattingTests'
    contains 'window classes: RelativeTimestampCaptureTests'
    excludes 'swift build'
    excludes "--filter '^HibossIslandTests\.(RelativeTimestampCaptureTests)/'"
    plan Sources/HibossIsland/Box/Browser/BoxBrowserDetail.swift
    contains 'tier: M2'
    contains 'window classes: BoxPolishLayoutTests'
    contains 'cd macos && swift build'
    contains "--filter '^HibossIslandTests\.(BoxPolishLayoutTests)/'"
    contains 'lockf -k /private/tmp/hiboss-macos-window-tests.lock caffeinate -d -i -u'
    plan macos/Tests/HibossIslandTests/IslandDropRevealTests.swift
    contains 'IslandDropRevealIntegrationTests, IslandDropRevealPolicyTests'
    contains '(IslandDropRevealIntegrationTests|IslandDropRevealPolicyTests)/'
    plan macos/Tests/HibossIslandTests/SharedFormattingTests.swift
    contains 'logic classes: SharedFormattingTests'
    excludes 'window classes: SharedFormattingTests'
}

check_shared_paths() {
    local path
    for path in MainView.swift Overview/OverviewSnapshot.swift Workspace/WorkspaceToolbar.swift \
        DesignTokens.swift Today/TodayStyle.swift; do
        plan "macos/Sources/HibossIsland/$path"
        contains 'tier: M3'
        contains 'cd macos && swift build'
        excludes "--filter '^HibossIslandTests\.'"
    done
    plan macos/Package.swift macos/Package.resolved
    contains 'tier: M3'
    excludes 'swift test'
    plan HibossKit/Sources/HibossKit/ProgressModelVendor.swift
    contains 'tier: M3'
    contains 'cd HibossKit && '
    contains "swift test --filter '^HibossKitTests\.(ProgressModelVendorTests)/'"
    contains 'cd macos && swift build'
}

check_missing_and_release() {
    plan macos/Sources/HibossIsland/VerifyTierUnreferencedNewFile.swift
    contains 'no test references macos/Sources/HibossIsland/VerifyTierUnreferencedNewFile.swift;'
    contains 'add a focused test'
    excludes 'swift test'
    output=$("$script" --files docs/macos-design-v2.md --release)
    cases=$((cases + 1))
    contains 'tier: M5'
    contains "swift test --filter '^HibossIslandTests\.'"
    contains 'lockf -k /private/tmp/hiboss-macos-window-tests.lock caffeinate -d -i -u'
    assert_rejected --run --files README.md
    assert_rejected --base
    assert_rejected --files
    assert_rejected --unknown
}

check_logged_audit() {
    mkdir "$temp/bin"
    cat > "$temp/bin/python3" <<'STUB'
#!/bin/sh
[ "$1" = macos/scripts/i18n-audit.py ] || exit 91
[ "$PWD" = "$VERIFY_TIER_EXPECTED_ROOT" ] || exit 92
echo 'audit stub executed'
exit "${VERIFY_TIER_AUDIT_EXIT:-0}"
STUB
    chmod +x "$temp/bin/python3"
    output=$(PATH="$temp/bin:$PATH" VERIFY_TIER_EXPECTED_ROOT="$root" \
        "$script" --files README.md --run --log "$temp/audit log")
    cases=$((cases + 1))
    contains 'audit stub executed'
    grep -F -q 'audit stub executed' "$temp/audit log" || fail 'missing logged output'
    checks=$((checks + 1))
    local status=0
    output=$(PATH="$temp/bin:$PATH" VERIFY_TIER_EXPECTED_ROOT="$root" VERIFY_TIER_AUDIT_EXIT=37 \
        "$script" --files README.md --run --log "$temp/failure log") || status=$?
    [ "$status" -eq 37 ] || fail 'audit failure exit code was lost through tee'
    cases=$((cases + 1))
    checks=$((checks + 1))
    contains 'audit stub executed'
    output=$("$script" --files macos/scripts/verify-tier.sh --run --log "$temp/empty log")
    cases=$((cases + 1))
    contains 'tier: M1'
    excludes 'swift test'
    [ -f "$temp/empty log" ] && [ ! -s "$temp/empty log" ] || fail 'empty plan was executed'
    checks=$((checks + 1))
}

check_git_collection() {
    cat > "$temp/bin/git" <<'STUB'
#!/bin/sh
shift 2
case "$*" in
    'diff --name-only fixture...HEAD --')
        echo macos/Sources/HibossIsland/Formatting/SharedTimestamp.swift ;;
    'diff --name-only HEAD --')
        echo macos/Sources/HibossIsland/Box/Browser/BoxBrowserDetail.swift ;;
    'ls-files --others --exclude-standard')
        echo macos/Sources/HibossIsland/VerifyTierUnreferencedNewFile.swift ;;
    'cat-file '*) exit 1 ;;
    *) exit 93 ;;
esac
STUB
    chmod +x "$temp/bin/git"
    output=$(PATH="$temp/bin:$PATH" "$script" --base fixture)
    cases=$((cases + 1))
    contains 'tier: M2'
    contains 'logic classes: SharedFormattingTests'
    contains 'window classes: BoxPolishLayoutTests, RelativeTimestampCaptureTests'
    contains 'no test references macos/Sources/HibossIsland/VerifyTierUnreferencedNewFile.swift;'
    output=$(PATH="$temp/bin:$PATH" "$script" --base invalid --files \
        macos/Sources/HibossIsland/VerifyTierUnreferencedNewFile.swift)
    cases=$((cases + 1))
    contains 'add a focused test'
    excludes 'swift test'
}

check_docs_and_strings
check_focused_classes
check_shared_paths
check_missing_and_release
check_logged_audit
check_git_collection
printf 'PASS: %s cases, %s assertions; 0 Swift commands executed\n' "$cases" "$checks"
