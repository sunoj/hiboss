#!/usr/bin/env python3
# Scans HibossKit sources for user-facing literals that bypass the package catalog.
# Usage: HibossKit/scripts/i18n-audit.py; exits 1 when findings remain.
# Flags human-looking literals outside kitL()/Text(verbatim:) and kitL keys absent from the catalog.

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "HibossKit"
CATALOG = SOURCES / "Resources" / "Localizable.xcstrings"

# Whole files whose literals are producer-authored demo content, not HibossKit copy.
SKIPPED_FILES = {
    "PanelFixtures.swift": "demo panel definitions stand in for agent-authored content",
    "PanelExampleFixtures.swift": "demo panel definitions stand in for agent-authored content",
    "PanelDemoProducer.swift": "demo producer names stand in for agent names",
    "PanelWebAssets.swift": "web renderer resource names",
    "L10n.swift": "bundle lookup helper",
}

# (file, line substring, reason) for deliberate, reviewed exceptions.
ALLOWLIST = [
    ("Domain.swift", 'return "iOS"', "platform brand name, not translated"),
    ("Domain.swift", 'return "Mac"', "platform brand name, not translated"),
    ("Domain.swift", 'return "Telegram"', "channel brand name, not translated"),
    ("Domain.swift", 'return "Discord"', "channel brand name, not translated"),
    ("Domain.swift", 'return "API"', "technical acronym for the API channel"),
    ("PanelTypes.swift", 'return "', "demo fixture titles for the offline panel demo (see PanelFixtures)"),
    ("Panels/PanelDashboardContent.swift", '"TextInput", "TextArea"', "panel component type identifiers"),
]

# Text immediately before a literal that marks it as machine data or already localized.
SAFE_PREFIX = re.compile(
    r"(kitL\(|verbatim:\s*|systemImage:\s*|systemName:\s*|==\s*|!=\s*|\[\s*|forKey:\s*|"
    r"forHTTPHeaderField:\s*|appendingPathComponent\(|URLQueryItem\(name:\s*|value:\s*|method:\s*|"
    r"context:\s*|debugDescription:\s*|forResource:\s*|withExtension:\s*|forURLScheme:\s*|name:\s*|"
    r"mimeType:\s*|textEncodingName:\s*|identifier:\s*|dateFormatter\(|URL\(string:\s*|of:\s*|with:\s*|"
    r"separator:\s*|purpose:\s*|alg:\s*|typ:\s*|algorithm:\s*|kind:\s*|panelId:\s*|platform: String =\s*|"
    r"hasPrefix\(|hasSuffix\(|contains\(|\.string\(|Data\(|callAsyncJavaScript\(|body:\s*|"
    r"setValue\(|subsystem:\s*|category:\s*|id:\s*|\.id\()$"
)
# SwiftUI initializers and modifiers whose literal argument becomes a Bundle.main LocalizedStringKey.
UI_CALL = re.compile(
    r"\b(Text|Button|Label|Toggle|TextField|SecureField|Picker|ProgressView|Section|GroupBox|Menu|Link|"
    r"LabeledContent|Stepper|DatePicker|accessibilityLabel|accessibilityHint|accessibilityValue|"
    r"navigationTitle|help|alert|confirmationDialog|value)\(\s*([^()\",:]*\?\s*)?$"
)
LITERAL = re.compile(r'(?<!#)"((?:[^"\\]|\\.)*)"')
HUMAN = re.compile(r"^[A-Z][a-z]+\b(?![.(])|[A-Za-z]{2,}[,:]? [A-Za-z]|[A-Za-z]{2,}[.…?!]$")
ALWAYS_BAD = [
    (re.compile(r"\bText\(\s*\""), "Text(\"…\") looks up Bundle.main; use Text(kitL(…)) or Text(verbatim:)"),
    (re.compile(r"String\(localized:(?![^\n]*bundle:)"), "String(localized:) without the package bundle"),
    (re.compile(r"\bLocalizedStringKey\("), "LocalizedStringKey resolves against Bundle.main"),
    (re.compile(r"\bNSLocalizedString\("), "NSLocalizedString without the package bundle"),
]


def code_part(line: str) -> str:
    """Strips a trailing // comment that is outside string literals."""
    in_string = False
    for index, char in enumerate(line):
        if char == '"' and (index == 0 or line[index - 1] != "\\"):
            in_string = not in_string
        if not in_string and line.startswith("//", index):
            return line[:index]
    return line


def case_pattern_end(code: str) -> int:
    """Returns the index of the `:` ending a `case` pattern, or -1."""
    stripped = code.lstrip()
    if not stripped.startswith("case ") or " = " in code.split(":")[0]:
        return -1
    in_string = False
    for index, char in enumerate(code):
        if char == '"' and code[index - 1] != "\\":
            in_string = not in_string
        if char == ":" and not in_string:
            return index
    return -1


def scan_line(name: str, number: int, raw: str) -> list[str]:
    code = code_part(raw)
    if not code.strip() or code.lstrip().startswith(("///", "*")):
        return []
    if any(file == name and marker in code for file, marker, _ in ALLOWLIST):
        return []
    findings = [f"{name}:{number}: {reason}" for pattern, reason in ALWAYS_BAD if pattern.search(code)]
    pattern_end = case_pattern_end(code)
    raw_value_case = re.search(r'\bcase\b[^"]*= "', code) is not None
    for match in LITERAL.finditer(code):
        text = re.sub(r"\\\(.*?\)", "", match.group(1))
        prefix = code[: match.start()]
        if UI_CALL.search(prefix) and re.search(r"[A-Za-z]", text):
            findings.append(f"{name}:{number}: literal \"{match.group(1)}\" in a SwiftUI localized-key position")
            continue
        if not HUMAN.search(text) or match.start() < pattern_end or raw_value_case:
            continue
        if SAFE_PREFIX.search(prefix):
            continue
        findings.append(f"{name}:{number}: literal \"{match.group(1)}\" bypasses kitL")
    return findings


KIT_KEY = re.compile(r'kitL\("((?:[^"\\]|\\.)*)"\)')
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*(?:\([^()]*\))?[^()]*\))*\)")


def missing_catalog_keys(path: Path, keys: set[str]) -> list[str]:
    """Reports kitL literals whose catalog key (interpolations as %@/%lld/%d) is absent."""
    findings = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for match in KIT_KEY.finditer(line):
            parts = INTERPOLATION.split(match.group(1))
            pattern = "%(?:lld|d|@|lf)".join(re.escape(part) for part in parts)
            if not any(re.fullmatch(pattern, key) for key in keys):
                findings.append(f"{path.name}:{number}: kitL key \"{match.group(1)}\" missing from catalog")
    return findings


def main() -> int:
    findings: list[str] = []
    keys = set(json.loads(CATALOG.read_text(encoding="utf-8"))["strings"])
    for path in sorted(SOURCES.rglob("*.swift")):
        findings.extend(missing_catalog_keys(path, keys))
        if path.name in SKIPPED_FILES:
            continue
        rel = str(path.relative_to(SOURCES))
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            findings.extend(scan_line(rel if "/" in rel else path.name, number, line))
    for finding in findings:
        print(finding)
    print("Deliberate exceptions:")
    for file, reason in SKIPPED_FILES.items():
        print(f"  skip {file}: {reason}")
    for file, marker, reason in ALLOWLIST:
        print(f"  allow {file} [{marker}]: {reason}")
    print(f"{len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
