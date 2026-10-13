#!/bin/bash
# Chooses focused macOS verification commands from changed paths or explicit files.
# Exports: CLI with --base, --files, --run --log, and explicit --release selection.
# Dependencies: macOS shell tools and verify-tier-discovery.sh; execution uses Swift/i18n tools.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$script_dir/../.." && pwd)
base=main
explicit=false
run=false
release=false
log=
files=()
commands=()

usage_error() {
    printf '%s\n' "$1" >&2
    printf 'usage: verify-tier.sh [--base ref] [--files path...] [--run --log file] [--release]\n' >&2
    exit 2
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --base|--log)
                [ "$#" -gt 1 ] && [ -n "$2" ] && [[ "$2" != --* ]] ||
                    usage_error "$1 requires a value"
                if [ "$1" = --base ]; then base=$2; else log=$2; fi
                shift 2
                ;;
            --files)
                explicit=true
                shift
                [ "$#" -gt 0 ] && [[ "$1" != --* ]] || usage_error '--files requires a path'
                while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do
                    files+=("$1")
                    shift
                done
                ;;
            --run) run=true; shift ;;
            --release) release=true; shift ;;
            *) usage_error "unknown argument: $1" ;;
        esac
    done
    [ "$run" = false ] || [ -n "$log" ] || usage_error '--run requires --log'
}

collect_paths() {
    if [ "$explicit" = true ]; then
        printf '%s\n' "${files[@]}" > "$temp/paths"
    else
        git -C "$root" diff --name-only "$base...HEAD" -- > "$temp/paths"
        git -C "$root" diff --name-only HEAD -- >> "$temp/paths"
        git -C "$root" ls-files --others --exclude-standard >> "$temp/paths"
    fi
    # --files accepts repository paths and the macOS package-relative paths used in test reports.
    sed -e 's|^\./||' -e 's|^Sources/HibossIsland/|macos/Sources/HibossIsland/|' \
        -e 's|^Tests/HibossIslandTests/|macos/Tests/HibossIslandTests/|' "$temp/paths" |
        LC_ALL=C sort -u > "$temp/changed"
}

class_list() {
    if [ -s "$1" ]; then paste -s -d ',' "$1" | sed 's/,/, /g'; else printf 'none\n'; fi
}

test_command() {
    local classes
    [ -s "$2" ] || return 0
    classes=$(paste -s -d '|' "$2")
    commands+=("cd $1 && $window_lock swift test --filter '^$3\.($classes)/'")
}

choose_tier() {
    tier=M1
    reason='non-view logic changes; focused logic tests only, matching window classes deferred'
    if [ "$code" = false ]; then
        tier=M0
        reason='documentation or localization only; no build'
    elif [ "$shared" = true ]; then
        tier=M3
        reason='shared UI, package inputs, or HibossKit changed'
    elif [ "$views" = true ] || [ "$window_changes" = true ]; then
        tier=M2
        reason='screen views, window construction, or window tests changed'
    fi
    if [ "$release" = true ]; then
        tier=M5
        reason='explicit release verification; full HibossIslandTests suite'
    fi
}

plan_commands() {
    window_lock='lockf -k /private/tmp/hiboss-macos-window-tests.lock caffeinate -d -i -u'
    if [ "$tier" = M0 ]; then
        commands+=('python3 macos/scripts/i18n-audit.py')
        return
    fi
    if [ "$tier" != M1 ]; then commands+=('cd macos && swift build'); fi
    if [ "$kit_changed" = true ]; then test_command HibossKit "$temp/kit" HibossKitTests; fi
    if [ "$tier" = M5 ]; then
        commands+=("cd macos && $window_lock swift test --filter '^HibossIslandTests\.'")
    else
        test_command macos "$temp/logic" HibossIslandTests
        if [ "$tier" != M1 ]; then test_command macos "$temp/windows" HibossIslandTests; fi
    fi
}

inspect_paths() {
    local path classes
    while IFS= read -r path; do
        case "$path" in *.md|docs/*|*/Localizable.xcstrings) continue ;; esac
        case "$path" in macos/*|HibossKit/*) code=true ;; *) continue ;; esac
        case "$path" in
            */MainView.swift|*/Overview/*|*/WorkspaceToolbar.swift|*/DesignTokens.swift|*TodayStyle*|\
            */Package.swift|*/Package.resolved|HibossKit/*) shared=true ;;
        esac
        case "$path" in HibossKit/*) kit_changed=true ;; esac
        case "$path" in
            macos/Sources/*.swift|HibossKit/Sources/*.swift)
                discover_source "$path"
                if grep -E -q 'NSWindow|NSPanel|NSHostingView|NSHostingController' "$temp/source"; then
                    window_changes=true
                fi
                ;;
            macos/Tests/*.swift|HibossKit/Tests/*.swift)
                if [ -f "$root/$path" ]; then
                    if grep -F -x -q "$root/$path" "$temp/window-files"; then window_changes=true; fi
                    swift_symbols classes "$root/$path" > "$temp/names"
                    select_classes mac
                    case "$path" in HibossKit/*) select_classes kit ;; esac
                fi
                ;;
        esac
    done < "$temp/changed"
    for classes in logic windows kit; do
        LC_ALL=C sort -u "$temp/$classes" -o "$temp/$classes"
    done
}

execute_commands() {
    local command
    [ "${#commands[@]}" -gt 0 ] || return 0
    for command in "${commands[@]}"; do
        printf '+ %s\n' "$command"
        (cd "$root" && eval "$command") || return "$?"
    done
}

parse_arguments "$@"
temp=$(mktemp -d "${TMPDIR:-/private/tmp}/hiboss-verify-tier.XXXXXX")
trap 'rm -r "$temp"' EXIT
. "$script_dir/verify-tier-discovery.sh"
for list in logic windows kit warnings; do : > "$temp/$list"; done
find "$root/macos/Tests/HibossIslandTests" -name '*.swift' -type f | LC_ALL=C sort > "$temp/mac-tests"
find "$root/HibossKit/Tests" -name '*.swift' -type f | LC_ALL=C sort > "$temp/kit-tests"
code=false
views=false
window_changes=false
shared=false
kit_changed=false
collect_paths
discover_windows
inspect_paths
choose_tier
plan_commands
printf 'tier: %s\nreason: %s\n' "$tier" "$reason"
printf 'logic classes: %s\n' "$(class_list "$temp/logic")"
printf 'window classes: %s\n' "$(class_list "$temp/windows")"
cat "$temp/warnings"
if [ "$kit_changed" = true ] && [ ! -s "$temp/kit" ]; then
    printf 'warning: no focused HibossKit test classes selected; add a focused test\n'
fi
if [ "${#commands[@]}" -gt 0 ]; then printf '%s\n' "${commands[@]}"; fi
if [ "$run" = true ]; then
    : > "$log"
    execute_commands 2>&1 | tee "$log"
fi
