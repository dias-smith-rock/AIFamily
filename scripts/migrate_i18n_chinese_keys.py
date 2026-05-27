#!/usr/bin/env python3
"""Migrate String Catalog + Swift sources from English keys to Chinese keys."""

from __future__ import annotations

import ast
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
REMINDER_DIR = ROOT / "reminder"
SCRIPT_ADD_I18N = ROOT / "scripts" / "add_i18n_keys.py"

# English keys we must NOT rewrite inside Swift (DB / debug / SF / URLs).
SKIP_LITERALS = frozenset({
    "male", "female", "entry", "invite",
    "List", "Day", "3 Day", "Week", "Month", "Year",  # CalendarViewMode rawValue
    "system", "light", "dark",
    "calendar", "clock", "person", "trash", "repeat", "banknote",
    "SIG", "WeFamily",
})

# Debug-only notification skip reasons — not user-facing catalog keys.
SKIP_PREFIXES = ("status_", "timed_", "allday_")


def load_add_i18n_mapping() -> dict[str, str]:
    text = SCRIPT_ADD_I18N.read_text(encoding="utf-8")
    tree = ast.parse(text)
    mapping: dict[str, str] = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name) and target.id == "NEW_KEYS":
                if isinstance(node.value, ast.Dict):
                    for key_node, val_node in zip(node.value.keys, node.value.values):
                        if key_node is None or val_node is None:
                            continue
                        en_key = ast.literal_eval(key_node)
                        val = ast.literal_eval(val_node)
                        if isinstance(val, dict) and "zh-Hans" in val:
                            zh = val["zh-Hans"]
                            if re.search(r"[\u4e00-\u9fff]", en_key) is None:
                                mapping[en_key] = zh
                            elif en_key != zh:
                                mapping[en_key] = zh
    return mapping


def extra_manual_mapping() -> dict[str, str]:
    return {
        "Dinner Together": "一起晚餐",
        "Grocery List": "杂货清单",
        "Kids Activity": "儿童活动",
        "List": "列表",
        "Day": "日",
        "3 Day": "3 天",
        "Week": "周",
        "Month": "月",
        "Year": "年",
        "Follow System": "跟随系统",
        "Light Mode": "浅色模式",
        "Dark Mode": "深色模式",
        "Light": "浅色",
        "Dark": "深色",
        "System": "系统",
        "Appearance": "外观",
        "Theme": "主题",
        "Language": "语言",
        "Notifications": "通知",
        "Integrations": "集成",
        "Text Size": "文字大小",
        "Support": "支持",
        "Privacy Policy": "隐私政策",
        "Terms of Service": "服务条款",
        "About WeFamily": "关于 WeFamily",
        "APP SETTINGS": "应用设置",
        "ACCOUNT": "账户",
        "Log Out": "退出登录",
        "Delete Account": "永久注销账号",
        "Upgrade to VIP": "升级 VIP",
        "Unlock premium features": "解锁高级功能",
        "Continue with Google": "使用 Google 继续",
        "More": "更多",
        "Close": "关闭",
        "Cancel": "取消",
        "Create": "创建",
        "Got it": "知道了",
        "Notice": "提示",
        "Today": "今天",
        "Custom": "自定义",
        "Never": "永不",
        "Import Events": "导入日程",
        "Organization Profile": "组织资料",
        "Create New Organization": "创建新组织",
        "Create Organization": "创建组织",
        "Enter organization name...": "输入组织名称…",
        "Switch organization": "切换组织",
        "Organization, %@, menu": "组织，%@，菜单",
        "No tasks scheduled today": "今天没有安排任务",
        "Enjoy your time together, or plan something new.": "享受共同时光，或者计划一些新的事情。",
        "From chaos to clarity.": "从混乱到清晰。",
        "From chaos to clarity.\nTogether, perfectly synced.": "从混乱到清晰。\n一起，完美同步。",
        "Together, perfectly synced.": "一起，完美同步。",
        "This event was synced from an external calendar and cannot be edited in the app.": "此日程由外部同步，暂不支持在应用内修改",
        "FaceTime, WhatsApp": "FaceTime、WhatsApp",
        "0 min": "0分钟",
        "%lld min": "%lld分钟",
        "%lld hr": "%lld小时",
        "%lld hr %lld min": "%lld小时%lld分钟",
        "%lld minutes before": "提前%lld分钟",
        "%lld people": "%lld 人",
        "Operation failed": "操作失败",
        "Please try again later.": "请稍后重试。",
        "Leave Group": "退出群组",
        "Disband Group": "解散群组",
        "Are you sure you want to leave this group?": "确定要退出该群组吗？",
        "Could not leave group": "退出群组失败",
        "Failed to rename the group. Please try again later.": "重命名群组失败，请稍后重试。",
        "Group name cannot be empty.": "群组名称不能为空。",
        "This group name is already taken. Please choose another name.": "该群组名称已被占用，请换一个名称。",
        "Only the creator or an admin can change the group name.": "仅创建者或管理员可以修改群组名称。",
        "channel: %@": "channel: %@",
        "nonce: %@": "nonce: %@",
        "token: %@": "token: %@",
        "valid: %@": "valid: %@",
        "What would you like to do? For example: tomorrow afternoon take the kids to the dentist…": "准备做什么？可以说：明天下午花 500 港币带老大去洗牙……",
        "No phone number needed—you can record tasks on their behalf (great for kids or elders).": "无需手机号，由您直接替 Ta 记录任务（适合小孩子或长辈）。",
        "From chaos to clarity.\nTogether, perfectly synced.": "从混乱到清晰。\n一起，完美同步。",
        "Untitled Organization": "未命名组织",
        "🔴 Urgent": "🔴 紧急",
        "🟢 Normal": "🟢 一般",
    }


def is_english_catalog_key(key: str) -> bool:
    if not key or key.strip() == "":
        return False
    if re.search(r"[\u4e00-\u9fff]", key):
        return False
    if key in SKIP_LITERALS:
        return False
    if any(key.startswith(p) for p in SKIP_PREFIXES):
        return False
    return bool(re.match(r"^[ -~]+$", key) or "\n" in key)


def merge_localizations(target: dict, source: dict) -> None:
    src_locs = source.get("localizations", {})
    dst_locs = target.setdefault("localizations", {})
    for locale, unit in src_locs.items():
        if locale not in dst_locs or not dst_locs[locale].get("stringUnit", {}).get("value"):
            dst_locs[locale] = unit


def migrate_xcstrings(mapping: dict[str, str]) -> tuple[int, int]:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]

    # Extend mapping from catalog entries that have zh-Hans
    for key, entry in list(strings.items()):
        if not is_english_catalog_key(key):
            continue
        zh = entry.get("localizations", {}).get("zh-Hans", {}).get("stringUnit", {}).get("value")
        if zh and key not in mapping:
            mapping[key] = zh

    migrated = 0
    removed = 0
    for en_key, zh_key in sorted(mapping.items(), key=lambda x: -len(x[0])):
        if en_key == zh_key:
            continue
        if en_key not in strings:
            continue
        en_entry = strings[en_key]
        if zh_key in strings:
            merge_localizations(strings[zh_key], en_entry)
        else:
            strings[zh_key] = en_entry
            migrated += 1
        del strings[en_key]
        removed += 1

    # Remove stale empty entries
    for key in list(strings.keys()):
        if strings[key] == {}:
            del strings[key]

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return migrated, removed


def replace_in_swift(mapping: dict[str, str]) -> int:
    # Longest keys first to avoid partial replacement
    items = sorted(mapping.items(), key=lambda x: -len(x[0]))
    total = 0
    for path in REMINDER_DIR.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        original = text
        for en, zh in items:
            if en == zh or en in SKIP_LITERALS:
                continue
            if len(en) < 3 and not en.startswith("%"):
                continue
            # Quoted string literals only
            text = text.replace(f'"{en}"', f'"{zh}"')
        if text != original:
            path.write_text(text, encoding="utf-8")
            total += 1
    return total


def count_remaining_english_keys() -> list[str]:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    return sorted(k for k in data["strings"] if is_english_catalog_key(k))


def main() -> None:
    mapping = load_add_i18n_mapping()
    mapping.update(extra_manual_mapping())

    migrated, removed = migrate_xcstrings(mapping)
    files_changed = replace_in_swift(mapping)
    remaining = count_remaining_english_keys()

    print(f"Mapping entries: {len(mapping)}")
    print(f"xcstrings: migrated {migrated} keys, removed {removed} English keys")
    print(f"Swift files updated: {files_changed}")
    print(f"Remaining English catalog keys: {len(remaining)}")
    for k in remaining[:40]:
        print(f"  {k!r}")
    if len(remaining) > 40:
        print(f"  ... and {len(remaining) - 40} more")


if __name__ == "__main__":
    main()
