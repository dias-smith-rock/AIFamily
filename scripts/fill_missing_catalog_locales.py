#!/usr/bin/env python3
"""Fill empty / incomplete String Catalog entries from catalog_gap_keys + add_i18n_keys."""

from __future__ import annotations

import ast
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
ADD_I18N_PATH = ROOT / "scripts" / "add_i18n_keys.py"
GAP_KEYS_PATH = ROOT / "scripts" / "catalog_gap_keys.py"
LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def make_entry(translations: dict[str, str]) -> dict:
    missing = [locale for locale in LOCALES if locale not in translations]
    if missing:
        raise ValueError(f"Missing locales {missing} for translations")
    return {"localizations": {locale: make_unit(translations[locale]) for locale in LOCALES}}


def load_add_i18n_keys() -> dict[str, dict[str, str]]:
    text = ADD_I18N_PATH.read_text(encoding="utf-8")
    tree = ast.parse(text)
    for node in tree.body:
        if isinstance(node, ast.Assign):
            target = node.targets[0]
            if isinstance(target, ast.Name) and target.id == "NEW_KEYS":
                return ast.literal_eval(node.value)
    return {}


def load_gap_keys() -> dict[str, dict[str, str]]:
    if GAP_KEYS_PATH.exists() is False:
        return {}
    namespace: dict = {}
    exec(GAP_KEYS_PATH.read_text(encoding="utf-8"), namespace)
    return namespace.get("GAP_KEYS", {})


def merge_sources() -> dict[str, dict[str, str]]:
    merged: dict[str, dict[str, str]] = {}
    merged.update(load_gap_keys())
    merged.update(load_add_i18n_keys())
    return merged


def main() -> None:
    sources = merge_sources()
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]

    added = 0
    updated = 0
    for key, translations in sources.items():
        if not key.strip():
            continue
        entry = make_entry(translations)
        if key not in strings:
            strings[key] = entry
            added += 1
            continue

        existing = strings[key].get("localizations") or {}
        if not existing:
            strings[key] = entry
            updated += 1
            continue

        changed = False
        for locale in LOCALES:
            if locale not in existing:
                existing[locale] = make_unit(translations[locale])
                changed = True
            else:
                value = existing[locale].get("stringUnit", {}).get("value", "")
                if not str(value).strip():
                    existing[locale] = make_unit(translations[locale])
                    changed = True
        if changed:
            strings[key] = {"localizations": existing}
            updated += 1

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Updated {XCSTRINGS_PATH}: sources={len(sources)} added={added} updated={updated}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
