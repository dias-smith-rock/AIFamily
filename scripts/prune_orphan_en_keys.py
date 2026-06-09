#!/usr/bin/env python3
"""Remove orphan English String Catalog keys that duplicate unused Chinese twins."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audit_i18n_duplicates import (
    XCSTRINGS_PATH,
    find_orphan_en_duplicates,
    load_swift_literals,
)

# Extra keys removed by safe-merge (no longer referenced after Swift updates).
EXTRA_REMOVABLE_KEYS = [
    "%lld 分钟",
    "Enjoying WeSync?",
    "好",
]


def main() -> int:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]
    swift = load_swift_literals()

    orphans = find_orphan_en_duplicates(strings, swift)
    to_remove = {en_key for en_key, _ in orphans}
    to_remove.update(EXTRA_REMOVABLE_KEYS)

    removed: list[str] = []
    for key in sorted(to_remove):
        if key in strings:
            del strings[key]
            removed.append(key)

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Removed {len(removed)} keys from {XCSTRINGS_PATH}")
    for key in removed:
        print(f"  - {key}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
