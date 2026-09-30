#!/usr/bin/env python3
# Re-runnable localization audit for macos/Sources: display-like literals that bypass the
# catalog, SwiftUI Bundle.main lookups, hand-rolled date formats, and L() keys missing
# from Localizable.xcstrings. Usage: scripts/i18n-audit.py; exits 1 on any finding.
"""A literal passes inside L(...), Text(verbatim:), or an identifier-only context.

Deliberate exceptions carry `// i18n-exempt: <reason>` on the literal's line, or
`// i18n-exempt-file: <reason>` anywhere in a file; each is listed with its reason.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
CATALOG = SOURCES / "HibossIsland" / "Resources" / "Localizable.xcstrings"
EXEMPT = re.compile(r"//\s*i18n-exempt:\s*(.*)$")
EXEMPT_FILE = re.compile(r"//\s*i18n-exempt-file:\s*(.*)$", re.M)
SAFE_BEFORE = re.compile(
    r"(\bL\(|verbatim:|systemImage:|systemName:|systemSymbolName:|accessibilityIdentifier\("
    r"|\bid:|forKey:|forResource:|withExtension:|subsystem:|category:|identifier:"
    r"|keyEquivalent:|named:|\blog(ger)?\.\w+\(|print\(|fatalError\(|precondition\w*\("
    r"|URL\(string:|charactersIn:|separator:|format:|uuidString:|forName:|rawValue:"
    r"|environment\[|userInfo\[|case\s+\w+\s*=|\.keyboardShortcut\(|CIFilter\(name:)\s*$"
)
UI_BEFORE = re.compile(
    r"(\b(Text|Button|Label|Toggle|Picker|Section|TextField|SecureField|Menu|LabeledContent"
    r"|Link|Window|GroupBox|DisclosureGroup|ContentUnavailableView|Stepper|ProgressView"
    r"|DatePicker)\(|\.(help|accessibilityLabel|accessibilityHint|accessibilityValue"
    r"|navigationTitle|alert|confirmationDialog|badge)\(|\b(title|toolTip|messageText"
    r"|informativeText|subtitle|placeholderString|stringValue)\s*=)\s*$"
)
DATE_SMELL = re.compile(r"dateFormat\s*=|String\(format:|\\\([^)]*\)(s|m|h|d|min|sec)\b")


def literals(code: str):
    """Yields (start, end, content) for top-level string literals; skips comments."""
    i, n = 0, len(code)
    while i < n:
        if code.startswith("//", i):
            i = code.find("\n", i) if "\n" in code[i:] else n
        elif code.startswith("/*", i):
            i = code.find("*/", i) + 2 if "*/" in code[i:] else n
        elif code[i] == '"':
            end = skip_string(code, i)
            quote = 3 if code.startswith('"""', i) else 1
            yield i, end, code[i + quote:end - quote]
            i = end
        else:
            i += 1


def skip_string(code: str, i: int) -> int:
    """Returns the index after the literal at i, honouring escapes and \\( ... ) nesting."""
    quote = '"""' if code.startswith('"""', i) else '"'
    i += len(quote)
    while i < len(code):
        if code[i] == "\\" and code.startswith("\\(", i):
            i, depth = i + 2, 1
            while i < len(code) and depth:
                if code[i] == '"':
                    i = skip_string(code, i)
                    continue
                depth += {"(": 1, ")": -1}.get(code[i], 0)
                i += 1
        elif code[i] == "\\":
            i += 2
        elif code.startswith(quote, i):
            return i + len(quote)
        else:
            i += 1
    return i


def is_display_text(text: str) -> bool:
    """True when a literal reads as prose rather than an identifier, key, or symbol."""
    bare = re.sub(r"\\\(.*?\)", "", text).strip()
    if not re.search(r"[A-Za-z]{2,}", bare):
        return False
    if " " not in bare and re.search(r"[._/:]|[a-z][A-Z]|^[a-z]", bare):
        return False
    return True


def scan_file(path: Path, code: str) -> tuple[list[str], list[str]]:
    findings: list[str] = []
    exemptions: list[str] = []
    lines = code.splitlines()
    rel = path.relative_to(ROOT)
    for start, _, text in literals(code):
        number = code.count("\n", 0, start) + 1
        line_start = code.rfind("\n", 0, code.rfind("\n", 0, start)) + 1
        before = re.sub(r"\s+", " ", code[line_start:start]).rstrip()
        if SAFE_BEFORE.search(before):
            continue
        if UI_BEFORE.search(before):
            issue = f'raw literal in a SwiftUI/AppKit label: "{text}"'
        elif is_display_text(text):
            issue = f'display-like literal outside L(): "{text}"'
        else:
            continue
        exempt = EXEMPT.search(lines[number - 1])
        if exempt:
            exemptions.append(f"{rel}:{number}: {exempt.group(1).strip() or 'NO REASON'}")
        else:
            findings.append(f"{rel}:{number}: {issue}")
    for number, line in enumerate(lines, 1):
        if not DATE_SMELL.search(line.split("//")[0]):
            continue
        exempt = EXEMPT.search(line)
        if exempt:
            exemptions.append(f"{rel}:{number}: {exempt.group(1).strip() or 'NO REASON'}")
        else:
            findings.append(f"{rel}:{number}: hand-rolled date/number format")
    return findings, exemptions


def split_interpolations(text: str) -> list[str]:
    """Literal text around each \\( ... ) interpolation, honouring nested parentheses."""
    parts, current, i = [], "", 0
    while i < len(text):
        if text.startswith("\\(", i):
            parts.append(current)
            current = ""
            i = close_paren(text, i + 2)
        else:
            current += text[i]
            i += 1
    return parts + [current]


def close_paren(text: str, i: int) -> int:
    depth = 1
    while i < len(text) and depth:
        depth += {"(": 1, ")": -1}.get(text[i], 0)
        i += 1
    return i


def missing_catalog_keys(code: str, rel: Path, keys: list[str]) -> list[str]:
    """L("...") keys absent from the catalog; interpolations match any format specifier."""
    missing = []
    for start, end, text in literals(code):
        if not re.search(r"\bL\(\s*$", code[max(0, start - 20):start]):
            continue
        parts = split_interpolations(text)
        pattern = "%(?:@|lld|ld|d|lf|f|arg)".join(re.escape(p.replace('\\"', '"')) for p in parts)
        if not any(re.fullmatch(pattern, key) for key in keys):
            missing.append(f"{rel}:{code.count(chr(10), 0, start) + 1}: key missing from catalog: \"{text}\"")
    return missing


def swiftui_bundle_main_keys() -> list[str]:
    """Literals SwiftUI would look up in Bundle.main (xcstringstool --SwiftUI extraction)."""
    if not shutil.which("xcrun"):
        return ["xcrun unavailable: SwiftUI extraction check skipped"]
    with tempfile.TemporaryDirectory() as out:
        files = [str(p) for p in SOURCES.rglob("*.swift")]
        subprocess.run(["xcrun", "xcstringstool", "extract", "--SwiftUI", "--omit-empty-stringsdata",
                        *files, "-o", out], check=True, capture_output=True)
        hits = []
        for data in Path(out).glob("*.stringsdata"):
            doc = json.loads(data.read_text())
            rel = Path(doc["source"]).resolve().relative_to(ROOT)
            for entries in doc["tables"].values():
                hits += [f"{rel}:{e['location']['startingLine']}: SwiftUI Bundle.main lookup of "
                         f"\"{e['key']}\" (use L(...) or verbatim:)" for e in entries]
        return hits


def main() -> int:
    keys = list(json.loads(CATALOG.read_text())["strings"])  # also proves the JSON is valid
    findings, exemptions = swiftui_bundle_main_keys(), []
    for path in sorted(SOURCES.rglob("*.swift")):
        code, rel = path.read_text(), path.relative_to(ROOT)
        findings += missing_catalog_keys(code, rel, keys)
        whole_file = EXEMPT_FILE.search(code)
        if whole_file:
            exemptions.append(f"{rel}: whole file: {whole_file.group(1).strip()}")
            continue
        file_findings, file_exemptions = scan_file(path, code)
        findings += file_findings
        exemptions += file_exemptions
    for line in findings:
        print(line)
    print(f"-- {len(exemptions)} deliberate exception(s):")
    for line in exemptions:
        print(f"   {line}")
    print(f"-- {len(findings)} finding(s)")
    return 1 if findings or any(e.endswith("NO REASON") for e in exemptions) else 0


if __name__ == "__main__":
    sys.exit(main())
