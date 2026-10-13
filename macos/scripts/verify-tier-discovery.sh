#!/bin/bash
# Discovers Swift declarations, focused XCTest classes, and window-using test files.
# Exports discovery functions sourced by verify-tier.sh.
# Dependencies: macOS awk, grep, sort, git, and the caller's root/temp paths.

swift_symbols() {
    awk -v mode="$1" '
        { sub(/\/\/.*$/, ""); text = text "\n" $0 }
        END {
            pattern = "(struct|class|enum|actor|protocol|extension)[[:space:]]+[A-Za-z_][A-Za-z_0-9]*"
            while (match(text, pattern)) {
                declaration = substr(text, RSTART)
                token = substr(text, RSTART, RLENGTH)
                split(token, words, /[[:space:]]+/)
                name = words[2]
                text = substr(text, RSTART + RLENGTH)
                if (name ~ /^(func|var|let|subscript)$/) continue
                sub(/\{.*/, "", declaration)
                if (mode == "types") print name
                if (mode == "classes" && words[1] == "class" &&
                    declaration ~ /:[[:space:]]*(XCTest\.)?XCTestCase([^A-Za-z_0-9]|$)/) print name
                if (mode == "view" && declaration ~ /:/ &&
                    declaration ~ /([^A-Za-z_0-9]|^)View([^A-Za-z_0-9]|$)/) print name
            }
        }
    ' "$2" | LC_ALL=C sort -u
}

references() {
    [ -s "$1" ] && grep -F -w -q -f "$1" "$2"
}

source_content() {
    if [ -f "$root/$1" ]; then
        cat "$root/$1"
    elif [ "$explicit" = true ]; then
        return 0
    elif git -C "$root" cat-file -e "HEAD:$1" 2>/dev/null; then
        git -C "$root" show "HEAD:$1"
    elif git -C "$root" cat-file -e "$base:$1" 2>/dev/null; then
        git -C "$root" show "$base:$1"
    fi
}

discover_windows() {
    local file previous
    local markers='NSWindow|NSPanel|NSHostingView|NSHostingController|orderFront|makeKeyAndOrderFront'
    # Compositor capture and the production Island controller also create real windows.
    markers="$markers|screencapture|IslandPanelController"
    : > "$temp/window-files"
    : > "$temp/window-symbols"
    while IFS= read -r file; do
        if grep -E -q "$markers" "$file"; then
            printf '%s\n' "$file" >> "$temp/window-files"
            swift_symbols types "$file" >> "$temp/window-symbols"
        fi
    done < "$temp/mac-tests"
    # Follow named capture helpers, including wrappers around other helpers.
    while :; do
        previous=$(wc -l < "$temp/window-files")
        while IFS= read -r file; do
            if ! grep -F -x -q "$file" "$temp/window-files" &&
                references "$temp/window-symbols" "$file"; then
                printf '%s\n' "$file" >> "$temp/window-files"
                swift_symbols types "$file" >> "$temp/window-symbols"
            fi
        done < "$temp/mac-tests"
        [ "$previous" -ne "$(wc -l < "$temp/window-files")" ] || break
    done
}

select_classes() {
    local file classes destination
    while IFS= read -r file; do
        references "$temp/names" "$file" || continue
        classes=$(swift_symbols classes "$file")
        [ -n "$classes" ] || continue
        matched=true
        destination="$temp/logic"
        if [ "$1" = kit ]; then
            destination="$temp/kit"
        elif grep -F -x -q "$file" "$temp/window-files"; then
            destination="$temp/windows"
        fi
        printf '%s\n' "$classes" >> "$destination"
    done < "$temp/$1-tests"
}

discover_source() {
    local name
    source_content "$1" > "$temp/source"
    swift_symbols types "$temp/source" > "$temp/names"
    name=${1##*/}
    printf '%s\n' "${name%.swift}" >> "$temp/names"
    [ -z "$(swift_symbols view "$temp/source")" ] || views=true
    matched=false
    select_classes mac
    case "$1" in HibossKit/*) select_classes kit ;; esac
    if [ "$matched" = false ]; then
        printf 'warning: no test references %s; add a focused test\n' "$1" >> "$temp/warnings"
    fi
}
