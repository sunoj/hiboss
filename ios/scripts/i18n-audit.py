#!/usr/bin/env python3
# Localization audit for the iOS app and widget: flags UI literals missing from the string
# catalogs, String variables passed where SwiftUI would render them unlocalized, and hand-rolled
# number/date formatting. Usage (from ios/): scripts/i18n-audit.py [--stringsdata <DerivedData>]
# Exits 0 with no output when clean; deliberate exceptions live in scripts/i18n-audit-allowlist.txt.
import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGETS = {"App": "App/Localizable.xcstrings", "Widgets": "Widgets/Localizable.xcstrings"}
SKIP_DIRS = ("App/Preview/",)
ALLOWLIST = os.path.join(ROOT, "scripts", "i18n-audit-allowlist.txt")

# Calls whose first argument SwiftUI/Foundation treats as a localization key when it is a literal.
KEYED_CALLS = (
    r"(?<![\w.])(?:Text|Label|Button|Toggle|Section|Picker|Menu|TextField|SecureField|DatePicker|"
    r"ProgressView|LabeledContent|ContentUnavailableView|Link)\(\s*"
    r"|\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint|"
    r"accessibilityValue|help)\(\s*"
    r"|String\(localized:\s*|LocalizedStringKey\(\s*|LocalizedStringResource\(\s*"
    r"|:\s*LocalizedStringResource\s*=\s*"
)
KEYED_RE = re.compile(KEYED_CALLS)
# Argument openings that are fine even when not a literal.
SAFE_ARG = re.compile(
    r"^(?:\"|verbatim:|String\(localized:|LocalizedStringKey\(|LocalizedStringResource\(|Text\(|"
    r"action:|intent:|role:|timerInterval:|isPresented:|isOn:|selection:|value:|text:|\)|\{|$)"
)
LOCALIZED_BRANCH = re.compile(r"^(?:String\(localized:|LocalizedStringKey\(|Text\()")
FORMATTED_ARG = re.compile(r"^[\w.\[\]()]+,\s*(?:format|style):")
HAND_FORMAT = [
    (re.compile(r"String\(format:"), "hand-rolled String(format:) — use FormatStyle"),
    (re.compile(r"\.joined\(separator:\s*\",\s*\"\)"), "hand-joined list — use .formatted(.list(...))"),
    (re.compile(r"\"[^\"]*\b(?:ago|mins?|secs?|hrs?)\b[^\"]*\""), "English time unit in a literal"),
]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|lf|u|llu|#@\w+@)")


def read_literal(src, start):
    """Return (normalized text, end index) of the Swift string literal opening at src[start]."""
    out, i, n = [], start + 1, len(src)
    while i < n:
        c = src[i]
        if c == "\\" and i + 1 < n and src[i + 1] == "(":
            depth, i = 1, i + 2
            while i < n and depth:
                depth += {"(": 1, ")": -1}.get(src[i], 0)
                i += 1
            out.append("\x00")
            continue
        if c == "\\" and i + 1 < n:
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(src[i + 1], src[i + 1]))
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        out.append(c)
        i += 1
    return "".join(out), n


def first_argument(rest):
    """The text of the first call argument: up to the depth-0 ',' or ')'."""
    depth = 0
    for i, c in enumerate(rest):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return rest[:i]
            depth -= 1
        elif c == "," and depth == 0:
            return rest[:i]
    return rest


def localized_ternary(arg):
    """True when arg is `cond ? A : B` and every branch is itself a localized value."""
    depth, parts, start, seen_q = 0, [], 0, False
    for i, c in enumerate(arg):
        depth += {"(": 1, ")": -1}.get(c, 0)
        if depth or c not in "?:" or arg[i - 1:i + 2].count("?") > 1:
            continue
        if c == "?" and not seen_q:
            seen_q, start = True, i + 1
        elif c == ":" and seen_q:
            parts.append(arg[start:i])
            start = i + 1
    if not seen_q:
        return False
    parts.append(arg[start:])
    return all(LOCALIZED_BRANCH.match(p.strip()) for p in parts)


def catalog_keys(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        keys = json.load(f)["strings"].keys()
    return {PLACEHOLDER.sub("\x00", k) for k in keys}


def code_lines(path):
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            if not line.lstrip().startswith("//"):
                yield number, line.rstrip("\n")


def scan_line(line, keys):
    """Yield (rule, message) findings for one source line."""
    for match in KEYED_RE.finditer(line):
        rest = line[match.end():]
        if rest.startswith('"') and not rest.startswith('"""'):
            text, _ = read_literal(rest, 0)
            if text and text not in keys:
                yield "missing-key", f"literal not in catalog: {text.replace(chr(0), '%@')!r}"
        elif not SAFE_ARG.match(rest) and not FORMATTED_ARG.match(rest) \
                and not localized_ternary(first_argument(rest)):
            if not match.group(0).startswith(("String(", "Localized", ":")):
                yield "unlocalized-var", "String value rendered without catalog lookup (use Text(verbatim:) for content)"
    for pattern, message in HAND_FORMAT:
        if pattern.search(line):
            yield "hand-format", message


def load_allowlist():
    entries = []
    if not os.path.exists(ALLOWLIST):
        return entries
    for raw in open(ALLOWLIST, encoding="utf-8"):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        parts = [p.strip() for p in raw.split("|")]
        if len(parts) != 4 or not parts[3]:
            sys.exit(f"i18n-audit: bad allowlist line (want path | rule | code | reason): {raw}")
        entries.append({"path": parts[0], "rule": parts[1], "code": parts[2], "used": False})
    return entries


def allowed(entries, path, rule, line):
    for entry in entries:
        if entry["path"] == path and entry["rule"] == rule and entry["code"] in line:
            entry["used"] = True
            return True
    return False


def source_findings(entries):
    findings = []
    for target, catalog in TARGETS.items():
        keys = catalog_keys(catalog)
        for path in sorted(glob.glob(os.path.join(ROOT, target, "**", "*.swift"), recursive=True)):
            rel = os.path.relpath(path, ROOT)
            if rel.startswith(SKIP_DIRS):
                continue
            for number, line in code_lines(path):
                for rule, message in scan_line(line, keys):
                    if not allowed(entries, rel, rule, line):
                        findings.append(f"{rel}:{number}: {rule}: {message}\n    {line.strip()}")
    return findings


def stringsdata_findings(derived, entries):
    """Exact check: keys the compiler extracted (SWIFT_EMIT_LOC_STRINGS=YES) but the catalog lacks."""
    findings = []
    for target, product in (("App", "HiBoss"), ("Widgets", "HiBossWidgets")):
        with open(os.path.join(ROOT, TARGETS[target]), encoding="utf-8") as f:
            keys = json.load(f)["strings"]
        pattern = os.path.join(derived, "Build/Intermediates.noindex/HiBoss.build/*",
                               f"{product}.build/Objects-normal/*/*.stringsdata")
        for data_path in sorted(glob.glob(pattern)):
            with open(data_path, encoding="utf-8") as f:
                data = json.load(f)
            rel = os.path.relpath(data.get("source", data_path), ROOT)
            for entry in data.get("tables", {}).get("Localizable", []):
                line = entry["key"]
                if line not in keys and not allowed(entries, rel, "extracted-key", line):
                    where = f"{rel}:{entry['location']['startingLine']}"
                    findings.append(f"{where}: extracted-key: compiler key not in {TARGETS[target]}: {line!r}")
    return sorted(set(findings))


def main():
    parser = argparse.ArgumentParser(description="Localization audit for ios/App and ios/Widgets.")
    parser.add_argument("--stringsdata", metavar="DERIVED_DATA",
                        help="also diff compiler-extracted keys from a SWIFT_EMIT_LOC_STRINGS=YES build")
    args = parser.parse_args()
    entries = load_allowlist()
    findings = source_findings(entries)
    if args.stringsdata:
        findings += stringsdata_findings(args.stringsdata, entries)
    stale = [e for e in entries if not e["used"] and (args.stringsdata or e["rule"] != "extracted-key")]
    for finding in findings:
        print(finding)
    for entry in stale:
        print(f"stale allowlist entry: {entry['path']} | {entry['rule']} | {entry['code']}")
    return 1 if findings or stale else 0


if __name__ == "__main__":
    sys.exit(main())
