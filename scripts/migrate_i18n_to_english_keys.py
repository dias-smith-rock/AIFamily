#!/usr/bin/env python3
"""Migrate String Catalog from Chinese keys to English snake_case keys."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from i18n_config import (
    KEY_OVERRIDES,
    KEYS_JSON,
    LOCALE_ORDER,
    LOCALIZATION_DIR,
    L10N_SWIFT,
    PATH_TABLE_RULES,
    REMINDER_DIR,
    SKIP_LITERALS,
    SKIP_PREFIXES,
    STALE_DROP_KEYS,
    TABLE_OVERRIDES,
    TABLES,
    XCSTRINGS_LEGACY,
)

SWIFT_UI_PATTERNS = [
    re.compile(r'(?:Text|TextField|SecureField|Section|navigationTitle|Button|Label|Toggle|ProgressView|DatePicker)\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'(?:header|footer|title|message|subtitle|primaryActionTitle|secondaryActionTitle):\s*\{\s*(?:\n\s*)?Text\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'(?:header|footer|title|message|subtitle|primaryActionTitle|secondaryActionTitle):\s*\{\s*(?:\n\s*)?"((?:\\.|[^"\\])*)"'),
    re.compile(r'(?:\.alert|confirmationDialog)\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'Button\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\btitle:\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\bsubtitle:\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\bprimaryActionTitle:\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\bsecondaryActionTitle:\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\.accessibilityLabel\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'mineSectionHeader\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'ProfileDetailRowView\s*\(\s*title:\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'return\s+"((?:\\.|[^"\\])*)"'),
    re.compile(r'case\s+[.\w]+:\s+"((?:\\.|[^"\\])*)"'),
    re.compile(r'default:\s+"((?:\\.|[^"\\])*)"'),
    re.compile(r'String\s*\(\s*localized:\s*(?:String\.LocalizationValue\s*\()?\\?"((?:\\.|[^"\\])*)"'),
    re.compile(r'AppLocalized\.(?:string|localized|localizedSync)\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'AppLocalized\.(?:string|localized|localizedSync)\s*\(\s*(?:String\.LocalizationValue\s*\()?\\?"((?:\\.|[^"\\])*)"'),
    re.compile(r'LocalizedStringKey\s*\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'Text\s*\(\s*"((?:\\.|[^"\\])*)"'),
]

COMMON_KEYWORDS = (
    "取消", "保存", "关闭", "知道了", "提示", "分钟", "小时", " 米", "千米", " 个",
    "今天", "明天", "加载", "请稍后", "操作失败", "确认", "删除", "完成", "更多",
    "跟随系统", "永不", "自定义", "%lld", "%@",
)


def load_legacy_catalog() -> dict:
    return json.loads(XCSTRINGS_LEGACY.read_text(encoding="utf-8"))


def slugify(text: str, max_len: int = 48) -> str:
    text = text.lower().strip()
    text = re.sub(r"[%@]", "", text)
    text = re.sub(r"[^\w\s-]", " ", text)
    text = re.sub(r"\s+", "_", text)
    text = re.sub(r"_+", "_", text).strip("_")
    if not text:
        text = "text"
    if text[0].isdigit():
        text = f"n_{text}"
    return text[:max_len].rstrip("_")


def table_prefix(table: str) -> str:
    return table.lower() + "_"


def infer_table_from_paths(paths: set[str]) -> str:
    if not paths:
        return "Common"
    scores: Counter[str] = Counter()
    for path in paths:
        for fragment, table in PATH_TABLE_RULES:
            if fragment in path:
                scores[table] += 1
    if scores:
        return scores.most_common(1)[0][0]
    return "Common"


def table_from_new_key(new_key: str) -> str | None:
    for table in TABLES:
        if new_key.startswith(table_prefix(table)):
            return table
    return None


def infer_table(legacy_key: str, paths: set[str], new_key: str | None = None) -> str:
    if new_key:
        by_prefix = table_from_new_key(new_key)
        if by_prefix:
            return by_prefix
    if legacy_key in TABLE_OVERRIDES:
        return TABLE_OVERRIDES[legacy_key]
    if any(kw in legacy_key for kw in COMMON_KEYWORDS) and len(paths) > 2:
        return "Common"
    table = infer_table_from_paths(paths)
    if legacy_key.startswith("👑") or "VIP" in legacy_key or "订阅" in legacy_key or "Pro" in legacy_key:
        return "VIP"
    if "登录" in legacy_key or "注册" in legacy_key or "会话" in legacy_key or "OAuth" in legacy_key:
        return "Auth"
    if "任务" in legacy_key or "日程" in legacy_key or "提醒" in legacy_key:
        return "Schedule"
    if "群组" in legacy_key or "组织" in legacy_key or "成员" in legacy_key or "邀请" in legacy_key:
        return "Family"
    if "位置" in legacy_key or "地图" in legacy_key or "隐身" in legacy_key:
        return "Location"
    if "反馈" in legacy_key:
        return "Feedback"
    if "助手" in legacy_key or "语音" in legacy_key:
        return "Assistant"
    return table


def scan_swift_references() -> dict[str, set[str]]:
    refs: dict[str, set[str]] = defaultdict(set)
    for path in REMINDER_DIR.rglob("*.swift"):
        if "Localization/L10n" in str(path):
            continue
        rel = str(path.relative_to(REMINDER_DIR))
        text = path.read_text(encoding="utf-8")
        for pattern in SWIFT_UI_PATTERNS:
            for match in pattern.findall(text):
                key = match.encode("utf-8").decode("unicode_escape") if "\\" in match else match
                refs[key].add(rel)
    return refs


def should_skip_key(key: str) -> bool:
    if not key or key.strip() == "":
        return True
    if key in SKIP_LITERALS:
        return True
    if any(key.startswith(p) for p in SKIP_PREFIXES):
        return True
    if key in STALE_DROP_KEYS:
        return True
    return False


def generate_new_key(legacy_key: str, table: str, en_value: str | None, used: set[str]) -> str:
    if legacy_key in KEY_OVERRIDES:
        candidate = KEY_OVERRIDES[legacy_key]
    elif re.match(r"^[ -~]+$", legacy_key) and not re.search(r"[\u4e00-\u9fff]", legacy_key):
        candidate = slugify(legacy_key)
        if not candidate.startswith(table_prefix(table)):
            candidate = table_prefix(table) + candidate
    else:
        base = slugify(en_value or legacy_key[:32])
        candidate = table_prefix(table) + base

    candidate = re.sub(r"[^a-z0-9_]", "_", candidate.lower())
    candidate = re.sub(r"_+", "_", candidate).strip("_")
    original = candidate
    suffix = 2
    while candidate in used:
        candidate = f"{original}_{suffix}"
        suffix += 1
    used.add(candidate)
    return candidate


def to_swift_property(new_key: str, table: str) -> str:
    prefix = table_prefix(table)
    rest = new_key[len(prefix):] if new_key.startswith(prefix) else new_key
    parts = [p for p in rest.split("_") if p]
    if not parts:
        return "key"
    name = parts[0]
    for part in parts[1:]:
        if part.isdigit():
            name += part
        else:
            name += part[0].upper() + part[1:]
    if name in {"default", "import", "switch", "return", "self", "Type"}:
        name += "Label"
    return name


def build_mapping(include_orphans: bool = True) -> list[dict]:
    catalog = load_legacy_catalog()
    strings = catalog["strings"]
    refs = scan_swift_references()
    used_keys: set[str] = set()
    entries: list[dict] = []

    for legacy_key in sorted(strings.keys(), key=lambda k: (-len(k), k)):
        if should_skip_key(legacy_key):
            continue
        entry = strings[legacy_key]
        locs = entry.get("localizations") or {}
        if not locs:
            continue
        paths = refs.get(legacy_key, set())
        is_orphan = len(paths) == 0 and legacy_key not in KEY_OVERRIDES and legacy_key not in TABLE_OVERRIDES
        if is_orphan and not include_orphans:
            continue
        table = infer_table(legacy_key, paths)
        en_value = locs.get("en", {}).get("stringUnit", {}).get("value")
        new_key = generate_new_key(legacy_key, table, en_value, used_keys)
        table = table_from_new_key(new_key) or infer_table(legacy_key, paths, new_key=new_key)
        entries.append({
            "legacy_key": legacy_key,
            "new_key": new_key,
            "table": table,
            "swift_property": to_swift_property(new_key, table),
            "orphan": is_orphan,
            "localizations": locs,
            "referenced_in": sorted(paths),
        })
    return entries


def write_keys_json(entries: list[dict]) -> None:
    KEYS_JSON.parent.mkdir(parents=True, exist_ok=True)
    payload = []
    for item in entries:
        payload.append({
            "legacy_key": item["legacy_key"],
            "new_key": item["new_key"],
            "table": item["table"],
            "swift_property": item["swift_property"],
            "orphan": item["orphan"],
        })
    KEYS_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_keys_entries() -> list[dict]:
    if not KEYS_JSON.exists():
        raise SystemExit(f"Missing {KEYS_JSON}; run generate-mapping first")
    raw = json.loads(KEYS_JSON.read_text(encoding="utf-8"))
    enriched = []
    for item in raw:
        locs = load_localizations_for_entry(item)
        if not locs:
            continue
        enriched.append({**item, "localizations": locs})
    return enriched


def write_catalogs(entries: list[dict]) -> None:
    LOCALIZATION_DIR.mkdir(parents=True, exist_ok=True)
    by_table: dict[str, dict] = defaultdict(dict)
    source_language = load_legacy_catalog().get("sourceLanguage", "zh-Hans")

    for item in entries:
        table = item["table"]
        new_key = item["new_key"]
        locs = item["localizations"]
        by_table[table][new_key] = {"localizations": locs}

    for table in TABLES:
        path = LOCALIZATION_DIR / f"{table}.xcstrings"
        data = {
            "sourceLanguage": source_language,
            "strings": dict(sorted(by_table.get(table, {}).items())),
            "version": "1.0",
        }
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {path} ({len(by_table.get(table, {}))} keys)")


def write_l10n(entries: list[dict]) -> None:
    LOCALIZATION_DIR.mkdir(parents=True, exist_ok=True)
    by_table: dict[str, list[dict]] = defaultdict(list)
    for item in entries:
        by_table[item["table"]].append(item)

    core = '''import Foundation
import SwiftUI

/// Type-safe accessors for split String Catalog tables (`Common`, `Settings`, …).
enum L10n {
    enum Table: String {
        case common = "Common"
        case settings = "Settings"
        case auth = "Auth"
        case schedule = "Schedule"
        case family = "Family"
        case location = "Location"
        case vip = "VIP"
        case todo = "Todo"
        case feedback = "Feedback"
        case assistant = "Assistant"
    }

    struct Entry {
        let key: String
        let table: Table

        var localized: LocalizedStringKey {
            L10n.key(key, table: table)
        }

        func string(locale: Locale) -> String {
            String(
                localized: String.LocalizationValue(key),
                table: table.rawValue,
                bundle: .main,
                locale: locale
            )
        }

        @MainActor
        func string() -> String {
            string(locale: AppSettingsManager.shared.appLocale)
        }

        func formatted(locale: Locale, _ arguments: CVarArg...) -> String {
            withVaList(arguments) { pointer in
                NSString(format: string(locale: locale), locale: locale, arguments: pointer) as String
            }
        }

        @MainActor
        func formatted(_ arguments: CVarArg...) -> String {
            formatted(locale: AppSettingsManager.shared.appLocale, arguments)
        }
    }

    static func key(_ key: String, table: Table) -> LocalizedStringKey {
        LocalizedStringKey(String.LocalizationValue(key), table: table.rawValue)
    }
}
'''
    L10N_SWIFT.write_text(core, encoding="utf-8")

    for table, items in sorted(by_table.items()):
        props = []
        seen_props: set[str] = set()
        for item in sorted(items, key=lambda x: x["swift_property"]):
            prop = item["swift_property"]
            if prop in seen_props:
                prop = prop + "Alt"
            seen_props.add(prop)
            props.append(
                f'    static let {prop} = Entry(key: "{item["new_key"]}", table: .{table.lower()})'
            )
        ext = f"\n// MARK: - {table}\n\nextension L10n {{\n    enum {table} {{\n"
        ext += "\n".join(props)
        ext += "\n    }\n}\n"
        path = LOCALIZATION_DIR / f"L10n+{table}.swift"
        path.write_text(f"import SwiftUI\n{ext}", encoding="utf-8")
        print(f"Wrote {path} ({len(props)} properties)")


def legacy_to_l10n_symbol(entries: list[dict]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    prop_counts: Counter[str] = Counter()
    for item in entries:
        prop_counts[(item["table"], item["swift_property"])] += 1

    for item in entries:
        prop = item["swift_property"]
        if prop_counts[(item["table"], prop)] > 1:
            prop = prop + "Alt"
        mapping[item["legacy_key"]] = f"L10n.{item['table']}.{prop}"
    return mapping


def apply_swift(entries: list[dict]) -> int:
    symbol_map = legacy_to_l10n_symbol(entries)
    replacements = sorted(symbol_map.items(), key=lambda x: -len(x[0]))
    changed_files = 0

    for path in REMINDER_DIR.rglob("*.swift"):
        if "Localization/L10n" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        for legacy, symbol in replacements:
            if legacy in SKIP_LITERALS:
                continue
            text = text.replace(f'"{legacy}"', symbol)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed_files += 1
    return changed_files


def merge_with_existing_entries(entries: list[dict]) -> list[dict]:
    if not KEYS_JSON.exists():
        return entries
    existing = {item["legacy_key"]: item for item in json.loads(KEYS_JSON.read_text(encoding="utf-8"))}
    merged = []
    seen_legacy: set[str] = set()
    for item in entries:
        legacy = item["legacy_key"]
        seen_legacy.add(legacy)
        if legacy in existing:
            preserved = existing[legacy]
            item["new_key"] = preserved["new_key"]
            item["table"] = table_from_new_key(preserved["new_key"]) or preserved["table"]
            item["swift_property"] = preserved.get("swift_property") or to_swift_property(item["new_key"], item["table"])
        merged.append(item)
    for legacy, preserved in existing.items():
        if legacy not in seen_legacy:
            merged.append(preserved)
    return merged


def apply_remaining_swift(entries: list[dict]) -> int:
    symbol_map = legacy_to_l10n_symbol(entries)
    replacements = sorted(symbol_map.items(), key=lambda x: -len(x[0]))
    changed_files = 0
    for path in REMINDER_DIR.rglob("*.swift"):
        if "Localization/L10n" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        for legacy, symbol in replacements:
            if legacy in SKIP_LITERALS:
                continue
            if f'"{legacy}"' not in text:
                continue
            text = text.replace(f'"{legacy}"', symbol)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed_files += 1
    return changed_files


def cmd_generate_mapping(args: argparse.Namespace) -> None:
    entries = build_mapping(include_orphans=args.include_orphans)
    entries = merge_with_existing_entries(entries)
    write_keys_json(entries)
    print(f"Generated {len(entries)} entries -> {KEYS_JSON}")


def cmd_apply_remaining(args: argparse.Namespace) -> None:
    if not KEYS_JSON.exists() or len(json.loads(KEYS_JSON.read_text())) < 100:
        cmd_generate_mapping(argparse.Namespace(include_orphans=True))
    entries = load_keys_entries()
    entries = refresh_entries_from_catalog(entries)
    if not entries:
        raise SystemExit("No catalog entries to write; restore reminder/Localizable.xcstrings first")
    write_keys_json(entries)
    files = apply_remaining_swift(entries)
    fix_swift_l10n_usage()
    write_catalogs(entries)
    write_l10n(entries)
    clear_legacy_catalog()
    print(f"Applied remaining strings in {files} Swift files")


def fix_swift_l10n_usage() -> int:
    """Append `.localized` where SwiftUI expects LocalizedStringKey."""
    patterns = [
        (re.compile(r'Text\((L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)\)'), r'Text(\1.localized)'),
        (re.compile(r'navigationTitle\((L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)\)'), r'navigationTitle(\1.localized)'),
        (re.compile(r'TextField\((L10n\.[A-Za-z]+\.[a-zA-Z0-9]+),'), r'TextField(\1.localized,'),
        (re.compile(r'Label\((L10n\.[A-Za-z]+\.[a-zA-Z0-9]+),'), r'Label(\1.localized,'),
        (re.compile(r'ProgressView\((L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)\)'), r'ProgressView(\1.localized)'),
        (re.compile(r'case ([^:]+): (L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)$', re.M), r'case \1: \2.localized'),
        (re.compile(r'default: (L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)$', re.M), r'default: \1.localized'),
        (re.compile(r'return (L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)$', re.M), r'return \1.localized'),
        (re.compile(r'String\(localized: (L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)\)'), r'\1.string()'),
        (re.compile(r'AppLocalized\.localized\((L10n\.[A-Za-z]+\.[a-zA-Z0-9]+)\)'), r'AppLocalized.localized(\1)'),
    ]
    changed = 0
    for path in REMINDER_DIR.rglob("*.swift"):
        if "Localization/L10n" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        for pattern, repl in patterns:
            text = pattern.sub(repl, text)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed += 1
    return changed


def load_localizations_for_entry(item: dict) -> dict:
    catalog = load_legacy_catalog()
    legacy = item["legacy_key"]
    locs = catalog.get("strings", {}).get(legacy, {}).get("localizations") or {}
    if locs:
        return locs
    table = item["table"]
    new_key = item["new_key"]
    split_path = LOCALIZATION_DIR / f"{table}.xcstrings"
    if split_path.exists():
        split = json.loads(split_path.read_text(encoding="utf-8"))
        return split.get("strings", {}).get(new_key, {}).get("localizations") or {}
    return {}


def refresh_entries_from_catalog(entries: list[dict]) -> list[dict]:
    refreshed = []
    for item in entries:
        locs = load_localizations_for_entry(item)
        if not locs:
            continue
        new_key = item["new_key"]
        table = table_from_new_key(new_key) or item.get("table") or "Common"
        item = {**item, "table": table, "localizations": locs}
        refreshed.append(item)
    return refreshed


def cmd_rebuild(args: argparse.Namespace) -> None:
    if KEYS_JSON.exists():
        entries = load_keys_entries()
        entries = refresh_entries_from_catalog(entries)
        write_keys_json(entries)
    else:
        cmd_generate_mapping(argparse.Namespace(include_orphans=False))
        entries = load_keys_entries()
    write_catalogs(entries)
    write_l10n(entries)
    files = fix_swift_l10n_usage()
    print(f"Rebuilt catalogs; fixed L10n usage in {files} Swift files")


def clear_legacy_catalog() -> None:
    if not XCSTRINGS_LEGACY.exists():
        return
    data = {
        "sourceLanguage": "zh-Hans",
        "strings": {},
        "version": "1.0",
    }
    XCSTRINGS_LEGACY.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Cleared {XCSTRINGS_LEGACY}")


def cmd_apply_all(args: argparse.Namespace) -> None:
    if not KEYS_JSON.exists():
        cmd_generate_mapping(argparse.Namespace(include_orphans=False))
    entries = load_keys_entries()
    write_catalogs(entries)
    write_l10n(entries)
    files = apply_swift(entries)
    fix_swift_l10n_usage()
    print(f"Updated {files} Swift files")


def cmd_finalize(args: argparse.Namespace) -> None:
    cmd_rebuild(argparse.Namespace())
    clear_legacy_catalog()


def main() -> None:
    parser = argparse.ArgumentParser(description="Migrate i18n to English snake_case keys")
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate-mapping", help="Build localization/keys.json from legacy catalog")
    gen.add_argument("--include-orphans", action="store_true")
    gen.set_defaults(func=cmd_generate_mapping)

    sub.add_parser("rebuild", help="Regenerate catalogs + L10n from keys.json").set_defaults(func=cmd_rebuild)

    sub.add_parser("finalize", help="Rebuild catalogs, fix Swift usage, clear legacy catalog").set_defaults(func=cmd_finalize)

    sub.add_parser("apply-remaining", help="Migrate remaining Chinese strings and rebuild catalogs").set_defaults(func=cmd_apply_remaining)

    apply = sub.add_parser("apply-all", help="Write catalogs, L10n, and patch Swift")
    apply.set_defaults(func=cmd_apply_all)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
