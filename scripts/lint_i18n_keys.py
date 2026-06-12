#!/usr/bin/env python3
"""Lint WeFamily split String Catalog + L10n conventions."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REMINDER_DIR = ROOT / "reminder"
LOCALIZATION_DIR = REMINDER_DIR / "Localization"
LEGACY_CATALOG = REMINDER_DIR / "Localizable.xcstrings"

CJK_UI = re.compile(
    r'(?:Text|TextField|SecureField|Section|navigationTitle|Button|Label|Toggle|'
    r'ProgressView|DatePicker|TextField|primaryActionTitle|secondaryActionTitle|'
    r'mineSectionHeader)\s*\(\s*"([^"]*[\u4e00-\u9fff][^"]*)"'
)

CJK_APPLocalized = re.compile(
    r'AppLocalized\.(?:string|localized|localizedSync)\s*\(\s*"([^"]*[\u4e00-\u9fff][^"]*)"'
)

SKIP_PATH_FRAGMENTS = (
    "AIParticipantHintMatcher",
    "AIPhotoTaskCreationLogger",
)


def load_catalog_keys() -> dict[str, set[str]]:
    tables: dict[str, set[str]] = {}
    for path in LOCALIZATION_DIR.glob("*.xcstrings"):
        table = path.stem
        data = json.loads(path.read_text(encoding="utf-8"))
        tables[table] = set(data.get("strings", {}).keys())
    return tables


def lint_swift_cjk() -> list[str]:
    errors: list[str] = []
    for path in REMINDER_DIR.rglob("*.swift"):
        if "Localization/L10n" in str(path):
            continue
        if any(skip in str(path) for skip in SKIP_PATH_FRAGMENTS):
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        is_view = "/Views/" in str(path)
        for line_no, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("//") or "print(" in line:
                continue
            if re.search(r'case\s+\w+\s*=\s*"[^"]*[\u4e00-\u9fff]', line):
                continue
            for pattern in (CJK_UI, CJK_APPLocalized):
                for match in pattern.findall(line):
                    if match.strip():
                        if is_view:
                            errors.append(f"{rel}:{line_no}: UI string still uses Chinese literal: {match!r}")
    return errors


def lint_empty_localizations() -> list[str]:
    errors: list[str] = []
    for path in LOCALIZATION_DIR.glob("*.xcstrings"):
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, entry in data.get("strings", {}).items():
            locs = entry.get("localizations") or {}
            if not locs:
                errors.append(f"{path.name}: empty localizations for {key!r}")
    return errors


def lint_legacy_catalog_gone() -> list[str]:
    if not LEGACY_CATALOG.exists():
        return []
    data = json.loads(LEGACY_CATALOG.read_text(encoding="utf-8"))
    nonempty = [
        k for k, v in data.get("strings", {}).items()
        if v.get("localizations") and k not in ("", " ")
    ]
    if nonempty:
        return [f"Legacy Localizable.xcstrings still has {len(nonempty)} non-empty keys"]
    return []


def main() -> int:
    errors: list[str] = []
    errors.extend(lint_swift_cjk())
    errors.extend(lint_empty_localizations())
    errors.extend(lint_legacy_catalog_gone())

    if errors:
        print("i18n lint FAILED:")
        for err in errors[:50]:
            print(f"  - {err}")
        if len(errors) > 50:
            print(f"  ... and {len(errors) - 50} more")
        return 1

    tables = load_catalog_keys()
    total = sum(len(v) for v in tables.values())
    print(f"i18n lint OK ({len(tables)} tables, {total} keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
