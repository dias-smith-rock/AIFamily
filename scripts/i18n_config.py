"""Shared constants for WeFamily i18n migration."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_LEGACY = ROOT / "reminder" / "Localizable.xcstrings"
KEYS_JSON = ROOT / "localization" / "keys.json"
LOCALIZATION_DIR = ROOT / "reminder" / "Localization"
REMINDER_DIR = ROOT / "reminder"
L10N_SWIFT = LOCALIZATION_DIR / "L10n.swift"

LOCALES = ["ar", "en", "es", "fr", "hi", "pt", "ta", "zh-Hans", "zh-Hant"]
LOCALE_ORDER = LOCALES

TABLES = [
    "Common",
    "Settings",
    "Auth",
    "Schedule",
    "Family",
    "Location",
    "VIP",
    "Todo",
    "Feedback",
    "Assistant",
]

# Non UI literals — never migrate.
SKIP_LITERALS = frozenset({
    "male", "female", "entry", "invite",
    "List", "Day", "3 Day", "Week", "Month", "Year",
    "system", "light", "dark",
    "calendar", "clock", "person", "trash", "repeat", "banknote",
    "SIG", "WeFamily", "Pro",
    "English", "Español", "Português", "Français", "हिन्दी", "தமிழ்",
    "العربية", "简体中文", "繁體中文",
    # AI participant hint matching (not UI copy)
    "全班", "全家", "所有人", "每位",
})

SKIP_PREFIXES = ("status_", "timed_", "allday_")

# Explicit table overrides for shared / ambiguous keys.
TABLE_OVERRIDES: dict[str, str] = {
    "5 分钟": "Common",
    "10 分钟": "Common",
    "15 分钟": "Common",
    "30 分钟": "Common",
    "1 小时": "Common",
    "100 米": "Common",
    "200 米": "Common",
    "300 米": "Common",
    "500 米": "Common",
    "1 千米": "Common",
    "2 千米": "Common",
    "3 个": "Common",
    "5 个": "Common",
    "10 个": "Common",
    "20 个": "Common",
    "取消": "Common",
    "保存": "Common",
    "关闭": "Common",
    "知道了": "Common",
    "提示": "Common",
    "今天": "Common",
    "更多": "Common",
    "创建": "Common",
    "删除": "Common",
    "确认": "Common",
    "完成": "Common",
    "加载中…": "Common",
    "请稍后重试。": "Common",
    "操作失败": "Common",
    "跟随系统": "Common",
    "位置上报": "Settings",
    "位置共享": "Settings",
    "位置隐身": "Settings",
    "位移阈值": "Settings",
    "上报间隔": "Settings",
    "历史位置数量": "Settings",
    "移动超过此距离后，才可能写入云端位置。": "Settings",
    "位移与间隔均达标时会新增一条位置记录；仅间隔到达而位移未达阈值时，会更新最近一条位置记录。": "Settings",
    "仅影响地图上显示的轨迹与历史点数量，不会改变云端存储的位置记录。": "Settings",
    "隐身期间不会向服务器上报新坐标，群组成员仍可看到您上次上报的位置。": "Settings",
}

# Explicit new_key overrides (legacy Chinese or English key -> new_key).
KEY_OVERRIDES: dict[str, str] = {
    "位置上报": "settings_location_reporting_nav_title",
    "位置共享": "settings_location_sharing_section",
    "位置隐身": "settings_location_ghost_toggle",
    "位移阈值": "settings_location_reporting_distance_section",
    "上报间隔": "settings_location_reporting_interval_section",
    "历史位置数量": "settings_location_reporting_history_count_section",
    "移动超过此距离后，才可能写入云端位置。": "settings_location_reporting_distance_footer",
    "位移与间隔均达标时会新增一条位置记录；仅间隔到达而位移未达阈值时，会更新最近一条位置记录。": "settings_location_reporting_interval_footer",
    "仅影响地图上显示的轨迹与历史点数量，不会改变云端存储的位置记录。": "settings_location_reporting_history_count_footer",
    "隐身期间不会向服务器上报新坐标，群组成员仍可看到您上次上报的位置。": "settings_location_ghost_footer",
    "5 分钟": "common_duration_5min",
    "10 分钟": "common_duration_10min",
    "15 分钟": "common_duration_15min",
    "30 分钟": "common_duration_30min",
    "1 小时": "common_duration_1hour",
    "100 米": "common_distance_100m",
    "200 米": "common_distance_200m",
    "300 米": "common_distance_300m",
    "500 米": "common_distance_500m",
    "1 千米": "common_distance_1km",
    "2 千米": "common_distance_2km",
    "3 个": "common_count_3",
    "5 个": "common_count_5",
    "10 个": "common_count_10",
    "20 个": "common_count_20",
    "取消": "common_cancel",
    "保存": "common_save",
    "关闭": "common_close",
    "知道了": "common_got_it",
    "提示": "common_notice",
    "今天": "common_today",
    "跟随系统": "common_follow_system",
}

# Stale duplicate keys to drop (superseded by another legacy key).
STALE_DROP_KEYS = frozenset({
    "",
    " ",
    "·",
    "仅当位移超过所选阈值，且距上次上报超过所选间隔时，才会写入云端位置。",
})

PATH_TABLE_RULES: list[tuple[str, str]] = [
    ("Views/Settings/VIP", "VIP"),
    ("Views/Settings/", "Settings"),
    ("Views/Location/", "Location"),
    ("Views/Schedule/", "Schedule"),
    ("Views/Todo/", "Todo"),
    ("Views/Family/", "Family"),
    ("Views/Feedback/", "Feedback"),
    ("Views/Assistant/", "Assistant"),
    ("Views/Root/Login", "Auth"),
    ("Views/Root/Auth", "Auth"),
    ("Views/Root/Session", "Auth"),
    ("Views/Root/Lock", "Auth"),
    ("Views/Root/Guest", "Auth"),
    ("Views/Root/OAuth", "Auth"),
    ("Views/Root/Pending", "Auth"),
    ("ViewModels/Auth", "Auth"),
    ("ViewModels/VIP", "VIP"),
    ("Services/StoreKit", "VIP"),
    ("Services/Subscription", "VIP"),
    ("ViewModels/Family", "Family"),
    ("ViewModels/Schedule", "Schedule"),
    ("ViewModels/Todo", "Todo"),
    ("ViewModels/Feedback", "Feedback"),
    ("ViewModels/Invite", "Family"),
    ("ViewModels/Transfer", "Family"),
    ("ViewModels/Mine", "Settings"),
    ("Views/Root/Mine", "Settings"),
    ("Views/Root/Household", "Family"),
    ("Views/Root/OrgRouting", "Family"),
    ("Views/Root/HouseholdSelection", "Family"),
]
