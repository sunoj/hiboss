#!/usr/bin/env python3
# Export, apply and check translations for every HiBoss string catalog (.xcstrings).
# Usage: i18n.py export <out.json> | apply <lang> <translations.json> | check
# Catalog ids and target languages are defined below; run from the repository root.
import json
import re
import subprocess
import sys
from pathlib import Path

CATALOGS = {
    "ios": "ios/App/Localizable.xcstrings",
    "ios-infoplist": "ios/App/InfoPlist.xcstrings",
    "widgets": "ios/Widgets/Localizable.xcstrings",
    "widgets-infoplist": "ios/Widgets/InfoPlist.xcstrings",
    "macos-infoplist": "macos/Sources/HibossIsland/Resources/InfoPlist.xcstrings",
    "macos": "macos/Sources/HibossIsland/Resources/Localizable.xcstrings",
    "kit": "HibossKit/Sources/HibossKit/Resources/Localizable.xcstrings",
}
LANGS = ["en", "zh-Hans", "th", "es", "hi", "ar", "pt-BR", "fr", "ja", "ko", "ru"]
# CLDR categories each language must provide for a plural string; extra ones are allowed.
PLURALS = {"en": {"one", "other"}, "es": {"one", "other"}, "fr": {"one", "other"},
           "pt-BR": {"one", "other"}, "hi": {"one", "other"}, "ru": {"one", "few", "many", "other"},
           "ar": {"zero", "one", "two", "few", "many", "other"},
           "zh-Hans": {"other"}, "ja": {"other"}, "ko": {"other"}, "th": {"other"}}
ALLOWED = {**{k: v | {"many"} for k, v in PLURALS.items() if k in ("es", "fr", "pt-BR")},
           **{k: v for k, v in PLURALS.items() if k not in ("es", "fr", "pt-BR")}}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|u|llu)")
SOURCE_DIRS = {"ios": ["ios/App"], "ios-infoplist": ["ios/App"], "widgets": ["ios/Widgets"], "widgets-infoplist": ["ios/Widgets"], "macos-infoplist": ["macos/Sources"],
               "macos": ["macos/Sources"], "kit": ["HibossKit/Sources"]}


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def save(path, data):
    text = json.dumps(data, ensure_ascii=False, indent=2)
    Path(path).write_text(text + "\n", encoding="utf-8")


def english(entry, key):
    unit = entry.get("localizations", {}).get("en", {})
    if "variations" in unit:
        return {c: v["stringUnit"]["value"] for c, v in unit["variations"]["plural"].items()}
    return unit.get("stringUnit", {}).get("value", key)


def usage_hint(catalog, key):
    needle = key.split("%")[0].strip()[:40]
    if len(needle) < 3:
        return ""
    for folder in SOURCE_DIRS[catalog]:
        result = subprocess.run(["grep", "-rn", "--include=*.swift", "-F", needle, folder],
                                capture_output=True, text=True)
        if result.stdout:
            return result.stdout.splitlines()[0][:200]
    return ""


def export(out):
    rows = {}
    for cid, path in CATALOGS.items():
        if not Path(path).exists():
            continue
        catalog = load(path)
        rows[cid] = {}
        for key, entry in catalog["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            rows[cid][key] = {"en": english(entry, key), "comment": entry.get("comment", ""),
                              "where": usage_hint(cid, key)}
    save(out, rows)
    print(f"exported {sum(len(v) for v in rows.values())} strings from {len(rows)} catalogs to {out}")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def apply(lang, source):
    translations = load(source)
    written = 0
    for cid, strings in translations.items():
        path = CATALOGS[cid]
        catalog = load(path)
        for key, value in strings.items():
            entry = catalog["strings"].get(key)
            if entry is None:
                sys.exit(f"{cid}: unknown key {key!r} in {source}")
            locs = entry.setdefault("localizations", {})
            if isinstance(value, dict):
                locs[lang] = {"variations": {"plural": {c: unit(v) for c, v in value.items()}}}
            else:
                locs[lang] = unit(value)
            written += 1
        save(path, catalog)
    print(f"{lang}: wrote {written} strings")


def placeholders(text):
    # Positional forms (%2$@) may reorder arguments; compare the argument types only.
    return sorted(re.sub(r"\d+\$", "", found) for found in PLACEHOLDER.findall(text))


def check_entry(cid, key, entry, problems):
    src = english(entry, key)
    src_ph = placeholders(src["other"] if isinstance(src, dict) else src)
    locs = entry.get("localizations", {})
    for lang in LANGS:
        loc = locs.get(lang)
        if lang == "en" and loc is None:
            continue  # key-as-source: English falls back to the key
        if loc is None:
            problems.append(f"{cid}: {key!r} missing {lang}")
            continue
        if "variations" in loc:
            forms = loc["variations"]["plural"]
            missing = PLURALS[lang] - set(forms)
            extra = set(forms) - ALLOWED[lang] - PLURALS[lang] - ({"zero", "one", "two", "few", "many"} if lang == "en" else set())
            if missing:
                problems.append(f"{cid}: {key!r} {lang} plural missing {sorted(missing)}")
            if extra and lang != "en":
                problems.append(f"{cid}: {key!r} {lang} plural has invalid {sorted(extra)}")
            texts = [f["stringUnit"]["value"] for f in forms.values()]
        else:
            texts = [loc["stringUnit"]["value"]]
        for text in texts:
            if src_ph and placeholders(text) != src_ph and not (isinstance(src, dict) and len(placeholders(text)) == 0):
                problems.append(f"{cid}: {key!r} {lang} placeholders {placeholders(text)} != {src_ph}")


def check():
    problems = []
    for cid, path in CATALOGS.items():
        if not Path(path).exists():
            continue
        for key, entry in load(path)["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            check_entry(cid, key, entry, problems)
    for line in problems[:200]:
        print(line)
    print(f"{len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "export":
        export(sys.argv[2])
    elif command == "apply":
        apply(sys.argv[2], sys.argv[3])
    elif command == "check":
        sys.exit(check())
    else:
        sys.exit(__doc__ or "usage: i18n.py export|apply|check")
