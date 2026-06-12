#!/usr/bin/env python3
"""Add catalog entries missing from the first migration pass."""

from __future__ import annotations

import json
from pathlib import Path

from i18n_config import KEYS_JSON, LOCALIZATION_DIR, LOCALE_ORDER

ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "reminder" / "Localizable.xcstrings"


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def make_locs(translations: dict[str, str]) -> dict:
    return {locale: make_unit(translations[locale]) for locale in LOCALE_ORDER if locale in translations}


def all_locales(en: str, zh_hans: str, zh_hant: str | None = None) -> dict[str, str]:
    zh_hant = zh_hant or zh_hans
    return {
        "en": en,
        "zh-Hans": zh_hans,
        "zh-Hant": zh_hant,
        "es": en,
        "pt": en,
        "fr": en,
        "ar": en,
        "hi": en,
        "ta": en,
    }


NEW_ENTRIES = [
    {
        "legacy_key": "从混乱到清晰。\n一起，完美同步。",
        "new_key": "auth_tagline_full",
        "table": "Auth",
        "swift_property": "taglineFull",
    },
    {
        "legacy_key": "未能读取 Apple 登录凭证。",
        "new_key": "auth_apple_credential_read_failed",
        "table": "Auth",
        "swift_property": "appleCredentialReadFailed",
        "translations": all_locales(
            "Could not read Apple sign-in credentials.",
            "未能读取 Apple 登录凭证。",
            "未能讀取 Apple 登入憑證。",
        ),
    },
    {
        "legacy_key": "未能获取 Apple identity token。",
        "new_key": "auth_apple_identity_token_failed",
        "table": "Auth",
        "swift_property": "appleIdentityTokenFailed",
        "translations": all_locales(
            "Could not obtain Apple identity token.",
            "未能获取 Apple identity token。",
            "未能取得 Apple identity token。",
        ),
    },
    {
        "legacy_key": "登录状态异常，请重试。",
        "new_key": "auth_session_abnormal_retry",
        "table": "Auth",
        "swift_property": "sessionAbnormalRetry",
        "translations": all_locales(
            "Sign-in state is invalid. Please try again.",
            "登录状态异常，请重试。",
            "登入狀態異常，請重試。",
        ),
    },
    {
        "legacy_key": "当前构建未启用 Sign in with Apple / Supabase，请使用 Google 登录。",
        "new_key": "auth_apple_supabase_unavailable_use_google",
        "table": "Auth",
        "swift_property": "appleSupabaseUnavailableUseGoogle",
        "translations": all_locales(
            "This build does not include Sign in with Apple / Supabase. Please sign in with Google.",
            "当前构建未启用 Sign in with Apple / Supabase，请使用 Google 登录。",
            "目前建置未啟用 Sign in with Apple / Supabase，請使用 Google 登入。",
        ),
    },
    {
        "legacy_key": "尚未载入你在当前群组的档案，请先在「群组」确认已加入群组。",
        "new_key": "settings_profile_not_loaded_in_group",
        "table": "Settings",
        "swift_property": "profileNotLoadedInGroup",
        "translations": all_locales(
            "Your profile in the current group is not loaded yet. Open Groups to confirm membership.",
            "尚未载入你在当前群组的档案，请先在「群组」确认已加入群组。",
            "尚未載入你在目前群組的檔案，請先在「群組」確認已加入群組。",
        ),
    },
    {
        "legacy_key": "群组，%@",
        "new_key": "family_group_accessibility_label",
        "table": "Family",
        "swift_property": "groupAccessibilityLabel",
        "translations": all_locales("Group, %@", "群组，%@", "群組，%@"),
    },
    {
        "legacy_key": "切换群组，%@",
        "new_key": "family_switch_group_accessibility_label",
        "table": "Family",
        "swift_property": "switchGroupAccessibilityLabel",
        "translations": all_locales("Switch group, %@", "切换群组，%@", "切換群組，%@"),
    },
    {
        "legacy_key": "每隔 %lld 天",
        "new_key": "schedule_recurrence_every_n_days",
        "table": "Schedule",
        "swift_property": "recurrenceEveryNDays",
        "translations": all_locales("Every %lld days", "每隔 %lld 天", "每隔 %lld 天"),
    },
    {
        "legacy_key": "第 %lld 张，共 %lld 张",
        "new_key": "schedule_attachment_page_indicator",
        "table": "Schedule",
        "swift_property": "attachmentPageIndicator",
        "translations": all_locales(
            "Image %lld of %lld",
            "第 %lld 张，共 %lld 张",
            "第 %lld 張，共 %lld 張",
        ),
    },
    {
        "legacy_key": "⚡️ 实时位置 · %lld 人在线",
        "new_key": "location_live_hud_online_count",
        "table": "Location",
        "swift_property": "liveHudOnlineCount",
        "translations": all_locales(
            "⚡️ Live location · %lld online",
            "⚡️ 实时位置 · %lld 人在线",
            "⚡️ 即時位置 · %lld 人在線",
        ),
    },
    {
        "legacy_key": "⚡️ 实时位置进行中（%lld 人）",
        "new_key": "location_live_ongoing_count",
        "table": "Location",
        "swift_property": "liveOngoingCount",
        "translations": all_locales(
            "⚡️ Live location active (%lld)",
            "⚡️ 实时位置进行中（%lld 人）",
            "⚡️ 即時位置進行中（%lld 人）",
        ),
    },
    {
        "legacy_key": "此操作不可逆！所有成员将被移除，任务、评论反馈及邀请码将被永久清空。请输入当前群组名称「%@」以确认解散。",
        "new_key": "family_disband_confirm_message",
        "table": "Family",
        "swift_property": "disbandConfirmMessage",
        "translations": all_locales(
            "This cannot be undone. All members will be removed and tasks, feedback, and invite codes will be permanently deleted. Type the group name \"%@\" to confirm.",
            "此操作不可逆！所有成员将被移除，任务、评论反馈及邀请码将被永久清空。请输入当前群组名称「%@」以确认解散。",
            "此操作不可逆！所有成員將被移除，任務、評論回饋及邀請碼將被永久清空。請輸入目前群組名稱「%@」以確認解散。",
        ),
    },
    {
        "legacy_key": "%lld 个待办已过期",
        "new_key": "todo_overdue_count",
        "table": "Todo",
        "swift_property": "overdueCount",
        "translations": all_locales("%lld to-dos overdue", "%lld 个待办已过期", "%lld 個待辦已過期"),
    },
    {
        "legacy_key": "您是「%@」等 %lld 个群组的创建者，请先转移权限或解散群组后再注销账户。",
        "new_key": "settings_delete_account_creator_block",
        "table": "Settings",
        "swift_property": "deleteAccountCreatorBlock",
        "translations": all_locales(
            "You are the creator of \"%@\" and %lld other groups. Transfer ownership or disband them before deleting your account.",
            "您是「%@」等 %lld 个群组的创建者，请先转移权限或解散群组后再注销账户。",
            "您是「%@」等 %lld 個群組的創建者，請先轉移權限或解散群組後再註銷帳戶。",
        ),
    },
    {
        "legacy_key": "二维码识别失败，请重试。",
        "new_key": "common_qr_recognition_failed_retry",
        "table": "Common",
        "swift_property": "qrRecognitionFailedRetry",
        "translations": all_locales(
            "QR code recognition failed. Please try again.",
            "二维码识别失败，请重试。",
            "QR 碼識別失敗，請重試。",
        ),
    },
    {
        "legacy_key": "当前设备不支持相机扫码。",
        "new_key": "common_camera_scan_unavailable",
        "table": "Common",
        "swift_property": "cameraScanUnavailable",
        "translations": all_locales(
            "Camera scanning is not available on this device.",
            "当前设备不支持相机扫码。",
            "目前裝置不支援相機掃碼。",
        ),
    },
    {
        "legacy_key": "相机当前不可用，请检查权限后重试。",
        "new_key": "common_camera_unavailable_check_permission",
        "table": "Common",
        "swift_property": "cameraUnavailableCheckPermission",
        "translations": all_locales(
            "Camera is unavailable. Check permissions and try again.",
            "相机当前不可用，请检查权限后重试。",
            "相機目前不可用，請檢查權限後重試。",
        ),
    },
    {
        "legacy_key": "邀请码生成失败，请稍后重试。",
        "new_key": "family_invite_code_generation_failed",
        "table": "Family",
        "swift_property": "inviteCodeGenerationFailed",
        "translations": all_locales(
            "Failed to generate invite code. Please try again later.",
            "邀请码生成失败，请稍后重试。",
            "邀請碼產生失敗，請稍後重試。",
        ),
    },
    {
        "legacy_key": "后端尚未完成升级，请先创建 get_or_create_invite_nonce RPC 后重试。",
        "new_key": "family_backend_invite_rpc_missing",
        "table": "Family",
        "swift_property": "backendInviteRpcMissing",
        "translations": all_locales(
            "Backend upgrade pending. Create the get_or_create_invite_nonce RPC and try again.",
            "后端尚未完成升级，请先创建 get_or_create_invite_nonce RPC 后重试。",
            "後端尚未完成升級，請先建立 get_or_create_invite_nonce RPC 後重試。",
        ),
    },
    {
        "legacy_key": "仅创建者或管理员可生成邀请二维码。",
        "new_key": "family_only_admin_can_generate_invite_qr",
        "table": "Family",
        "swift_property": "onlyAdminCanGenerateInviteQr",
        "translations": all_locales(
            "Only the creator or an admin can generate an invite QR code.",
            "仅创建者或管理员可生成邀请二维码。",
            "僅創建者或管理員可產生邀請 QR 碼。",
        ),
    },
    {
        "legacy_key": "未识别到有效邀请码，请重试。",
        "new_key": "family_no_valid_invite_code_detected",
        "table": "Family",
        "swift_property": "noValidInviteCodeDetected",
        "translations": all_locales(
            "No valid invite code detected. Please try again.",
            "未识别到有效邀请码，请重试。",
            "未識別到有效邀請碼，請重試。",
        ),
    },
    {
        "legacy_key": "图片读取失败，请换一张清晰二维码图片。",
        "new_key": "family_qr_image_read_failed",
        "table": "Family",
        "swift_property": "qrImageReadFailed",
        "translations": all_locales(
            "Failed to read the image. Try a clearer QR code photo.",
            "图片读取失败，请换一张清晰二维码图片。",
            "圖片讀取失敗，請換一張清晰 QR 碼圖片。",
        ),
    },
    {
        "legacy_key": "我是家长",
        "new_key": "family_i_am_a_parent",
        "table": "Family",
        "swift_property": "iAmAParent",
        "translations": all_locales("I'm a parent", "我是家长", "我是家長"),
    },
    {
        "legacy_key": "创建一个全新的群组空间",
        "new_key": "family_create_brand_new_group_space",
        "table": "Family",
        "swift_property": "createBrandNewGroupSpace",
        "translations": all_locales(
            "Create a brand-new group space",
            "创建一个全新的群组空间",
            "建立一個全新的群組空間",
        ),
    },
    {
        "legacy_key": "通过扫码或邀请码加入",
        "new_key": "family_join_via_scan_or_invite_code",
        "table": "Family",
        "swift_property": "joinViaScanOrInviteCode",
        "translations": all_locales(
            "Join via scan or invite code",
            "通过扫码或邀请码加入",
            "透過掃碼或邀請碼加入",
        ),
    },
    {
        "legacy_key": "全部",
        "new_key": "feedback_filter_all",
        "table": "Feedback",
        "swift_property": "filterAll",
        "translations": all_locales("All", "全部", "全部"),
    },
    {
        "legacy_key": "未读",
        "new_key": "feedback_filter_unread",
        "table": "Feedback",
        "swift_property": "filterUnread",
        "translations": all_locales("Unread", "未读", "未讀"),
    },
    {
        "legacy_key": "还没有反馈消息",
        "new_key": "feedback_no_messages_yet",
        "table": "Feedback",
        "swift_property": "noMessagesYet",
        "translations": all_locales(
            "No feedback yet",
            "还没有反馈消息",
            "還沒有回饋訊息",
        ),
    },
    {
        "legacy_key": "筛选后暂无消息",
        "new_key": "feedback_no_filtered_messages",
        "table": "Feedback",
        "swift_property": "noFilteredMessages",
        "translations": all_locales(
            "No messages match this filter",
            "筛选后暂无消息",
            "篩選後暫無訊息",
        ),
    },
    {
        "legacy_key": "成员提交语音反馈后会出现在这里。",
        "new_key": "feedback_voice_messages_appear_here",
        "table": "Feedback",
        "swift_property": "voiceMessagesAppearHere",
        "translations": all_locales(
            "Voice feedback from members will appear here.",
            "成员提交语音反馈后会出现在这里。",
            "成員提交語音回饋後會出現在這裡。",
        ),
    },
    {
        "legacy_key": "当前筛选条件下没有匹配项，试试切换到“全部”。",
        "new_key": "feedback_try_switch_to_all_filter",
        "table": "Feedback",
        "swift_property": "trySwitchToAllFilter",
        "translations": all_locales(
            "Nothing matches the current filter. Try switching to All.",
            "当前筛选条件下没有匹配项，试试切换到“全部”。",
            "目前篩選條件下沒有符合項目，試試切換到「全部」。",
        ),
    },
    {
        "legacy_key": "查看全部消息",
        "new_key": "feedback_view_all_messages",
        "table": "Feedback",
        "swift_property": "viewAllMessages",
        "translations": all_locales(
            "View all messages",
            "查看全部消息",
            "查看全部訊息",
        ),
    },
    {
        "legacy_key": "仅看未读",
        "new_key": "feedback_unread_only",
        "table": "Feedback",
        "swift_property": "unreadOnly",
        "translations": all_locales("Unread only", "仅看未读", "僅看未讀"),
    },
    {
        "legacy_key": "系统消息",
        "new_key": "feedback_system_message",
        "table": "Feedback",
        "swift_property": "systemMessage",
        "translations": all_locales("System message", "系统消息", "系統訊息"),
    },
    {
        "legacy_key": "未设置地点",
        "new_key": "feedback_location_not_set",
        "table": "Feedback",
        "swift_property": "locationNotSet",
        "translations": all_locales(
            "Location not set",
            "未设置地点",
            "未設定地點",
        ),
    },
    {
        "legacy_key": "请先登录后再订阅。",
        "new_key": "vip_sign_in_before_subscribe",
        "table": "VIP",
        "swift_property": "signInBeforeSubscribe",
        "translations": all_locales(
            "Please sign in before subscribing.",
            "请先登录后再订阅。",
            "請先登入後再訂閱。",
        ),
    },
    {
        "legacy_key": "未进入组织",
        "new_key": "common_not_in_organization",
        "table": "Common",
        "swift_property": "notInOrganization",
        "translations": all_locales(
            "Not in an organization",
            "未进入组织",
            "未進入組織",
        ),
    },
    {
        "legacy_key": "可以让 AI 帮你快速创建一条群组任务。",
        "new_key": "schedule_ai_create_task_hint",
        "table": "Schedule",
        "swift_property": "aiCreateTaskHint",
        "translations": all_locales(
            "Let AI help you quickly create a group task.",
            "可以让 AI 帮你快速创建一条群组任务。",
            "可以讓 AI 幫你快速建立一條群組任務。",
        ),
    },
    {
        "legacy_key": "让 AI 帮我创建",
        "new_key": "schedule_let_ai_create_for_me",
        "table": "Schedule",
        "swift_property": "letAiCreateForMe",
        "translations": all_locales(
            "Let AI create for me",
            "让 AI 帮我创建",
            "讓 AI 幫我建立",
        ),
    },
    {
        "legacy_key": "手动新建",
        "new_key": "schedule_create_manually",
        "table": "Schedule",
        "swift_property": "createManually",
        "translations": all_locales(
            "Create manually",
            "手动新建",
            "手動新建",
        ),
    },
]


def legacy_locs(legacy_key: str) -> dict | None:
    if not LEGACY.exists():
        return None
    data = json.loads(LEGACY.read_text(encoding="utf-8"))
    locs = data.get("strings", {}).get(legacy_key, {}).get("localizations")
    return locs or None


def main() -> None:
    keys = json.loads(KEYS_JSON.read_text(encoding="utf-8")) if KEYS_JSON.exists() else []
    existing_legacy = {item["legacy_key"] for item in keys}

    for entry in NEW_ENTRIES:
        legacy = entry["legacy_key"]
        if legacy in existing_legacy:
            continue
        locs = entry.get("translations")
        if locs:
            locs = make_locs(locs)
        else:
            locs = legacy_locs(legacy)
        if not locs:
            print(f"SKIP no translations: {legacy!r}")
            continue
        keys.append({
            "legacy_key": legacy,
            "new_key": entry["new_key"],
            "table": entry["table"],
            "swift_property": entry["swift_property"],
            "orphan": False,
        })
        table_path = LOCALIZATION_DIR / f"{entry['table']}.xcstrings"
        catalog = json.loads(table_path.read_text(encoding="utf-8"))
        catalog.setdefault("strings", {})[entry["new_key"]] = {"localizations": locs}
        table_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Added {entry['new_key']} -> {entry['table']}")

    KEYS_JSON.write_text(json.dumps(keys, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Regenerate L10n extensions for new keys only
    from migrate_i18n_to_english_keys import load_keys_entries, write_l10n
    write_l10n(load_keys_entries())


if __name__ == "__main__":
    main()
