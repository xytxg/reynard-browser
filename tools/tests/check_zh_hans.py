#!/usr/bin/env python3
"""Validate non-empty, reviewed Simplified Chinese XCStrings and format placeholders."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = (
    Path("browser/Reynard/Resources/Localizable.xcstrings"),
    Path("browser/Reynard/Client/Interface/Library/Settings/SettingsLocalizable.xcstrings"),
)
FORMAT = re.compile(r"(?<!%)%(?:\d+\$)?[-+ 0#]*(?:\d+)?(?:\.\d+)?[diouxXfFeEgGaAcCsSp@]")

def placeholders(s: str) -> list[str]:
    return sorted(m.group()[-1] for m in FORMAT.finditer(s))

def translated_value(entry):
    if not isinstance(entry, dict):
        return None
    unit = entry.get("stringUnit")
    if unit is not None:
        return unit if isinstance(unit, dict) else None
    variations = entry.get("variations", {}).get("plural", {})
    if isinstance(variations, dict):
        variant = variations.get("other", {}).get("stringUnit")
        return variant if isinstance(variant, dict) else None
    return None

def run() -> int:
    problems = []
    total = 0
    for relpath in CATALOGS:
        try:
            document = json.loads((ROOT / relpath).read_text(encoding="utf-8"))
            strings = document["strings"]
        except (OSError, KeyError, ValueError, TypeError) as exc:
            problems.append(f"{relpath}: unreadable catalog: {exc}")
            continue
        for key, entry in strings.items():
            total += 1
            langs = entry.get("localizations", {})
            unit = translated_value(langs.get("zh-Hans"))
            if unit is None or unit.get("state") != "translated" or not isinstance(unit.get("value"), str) or not unit["value"].strip():
                problems.append(f"{relpath}: missing/unreviewed zh-Hans: {key!r}")
                continue
            english = translated_value(langs.get("en"))
            reference = english.get("value") if english and english.get("value") else key
            if placeholders(reference) != placeholders(unit["value"]):
                problems.append(f"{relpath}: format mismatch: {key!r}")
        print(f"{relpath}: {len(strings)} keys checked")
    print(f"{total} strings validated")
    for issue in problems:
        print("ERROR:", issue, file=sys.stderr)
    return 1 if problems else 0

if __name__ == "__main__":
    sys.exit(run())
