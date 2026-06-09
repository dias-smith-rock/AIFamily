#!/usr/bin/env python3
"""Audit String Catalog for orphan English keys that duplicate Chinese twins."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
REMINDER_DIR = ROOT / "reminder"
LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]


def is_chinese_key(key: str) -> bool:
    return bool(re.search(r"[\u4e00-\u9fff]", key))


def en_value(entry: dict) -> str:
    locs = entry.get("localizations") or {}
    return locs.get("en", {}).get("stringUnit", {}).get("value", "")


def load_swift_literals() -> str:
    return "".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in REMINDER_DIR.rglob("*.swift")
    )


def key_referenced_in_swift(key: str, swift: str) -> bool:
    return f'"{key}"' in swift


def find_orphan_en_duplicates(strings: dict, swift: str) -> list[tuple[str, str]]:
    by_en: dict[str, list[str]] = {}
    for key, entry in strings.items():
        if not key.strip():
            continue
        value = en_value(entry)
        if value:
            by_en.setdefault(value, []).append(key)

    removable: list[tuple[str, str]] = []
    for _en, keys in by_en.items():
        chinese = [k for k in keys if is_chinese_key(k)]
        english = [k for k in keys if not is_chinese_key(k)]
        if not chinese:
            continue
        keep = chinese[0]
        for en_key in english:
            if key_referenced_in_swift(en_key, swift) is False:
                removable.append((en_key, keep))
    return sorted(removable, key=lambda pair: pair[0])


def catalog_health(strings: dict) -> tuple[int, int]:
    empty = 0
    incomplete = 0
    for key, entry in strings.items():
        if not key.strip():
            empty += 1
            continue
        locs = entry.get("localizations") or {}
        if not locs:
            empty += 1
            continue
        if any(locale not in locs for locale in LOCALES):
            incomplete += 1
    return empty, incomplete


def main() -> int:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]
    swift = load_swift_literals()
    orphans = find_orphan_en_duplicates(strings, swift)
    empty, incomplete = catalog_health(strings)

    print(f"Catalog keys: {len(strings)}")
    print(f"Empty entries: {empty}")
    print(f"Incomplete locale coverage: {incomplete}")
    print(f"Orphan English duplicates (safe to prune): {len(orphans)}")
    for en_key, cn_key in orphans:
        print(f"  {en_key!r} -> keep {cn_key!r}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
