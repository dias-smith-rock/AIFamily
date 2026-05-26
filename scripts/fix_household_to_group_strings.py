#!/usr/bin/env python3
"""Migrate household/family user-facing copy to group semantics in Localizable.xcstrings."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def make_entry(translations: dict[str, str]) -> dict:
    return {"localizations": {locale: make_unit(translations[locale]) for locale in LOCALES}}


# old_key -> (new_key, translations)
KEY_MIGRATIONS: dict[str, tuple[str, dict[str, str]]] = {
    "Failed to create household. Please try again later.": (
        "Failed to create group. Please try again later.",
        {
            "en": "Failed to create group. Please try again later.",
            "zh-Hans": "创建群组失败，请稍后重试。",
            "zh-Hant": "建立群組失敗，請稍後重試。",
            "es": "No se pudo crear el grupo. Inténtelo de nuevo más tarde.",
            "pt": "Falha ao criar o grupo. Tente novamente mais tarde.",
            "fr": "Échec de la création du groupe. Veuillez réessayer plus tard.",
            "ar": "فشل إنشاء المجموعة. يرجى المحاولة مرة أخرى لاحقًا.",
            "hi": "समूह बनाने में विफल। कृपया बाद में पुनः प्रयास करें।",
            "ta": "குழுவை உருவாக்க முடியவில்லை. பிறகு மீண்டும் முயற்சிக்கவும்.",
        },
    ),
    "Could not join the household. Please try again later or contact the creator.": (
        "Could not join the group. Please try again later or contact the creator.",
        {
            "en": "Could not join the group. Please try again later or contact the creator.",
            "zh-Hans": "加入群组失败，请稍后重试或联系群组创建者。",
            "zh-Hant": "加入群組失敗，請稍後重試或聯絡群組建立者。",
            "es": "No se pudo unir al grupo. Inténtelo de nuevo más tarde o contacte al creador.",
            "pt": "Não foi possível entrar no grupo. Tente novamente mais tarde ou contate o criador.",
            "fr": "Impossible de rejoindre le groupe. Veuillez réessayer plus tard ou contacter le créateur.",
            "ar": "تعذر الانضمام إلى المجموعة. يرجى المحاولة لاحقًا أو التواصل مع المنشئ.",
            "hi": "समूह में शामिल नहीं हो सके। कृपया बाद में पुनः प्रयास करें या निर्माता से संपर्क करें।",
            "ta": "குழுவில் சேர முடியவில்லை. பிறகு மீண்டும் முயற்சிக்கவும் அல்லது உருவாக்குநரை தொடர்பு கொள்ளவும்.",
        },
    ),
    "Household name cannot be empty. Please enter a name before creating.": (
        "Group name cannot be empty. Please enter a name before creating.",
        {
            "en": "Group name cannot be empty. Please enter a name before creating.",
            "zh-Hans": "群组名称不能为空，请输入后再创建。",
            "zh-Hant": "群組名稱不能為空，請輸入後再建立。",
            "es": "El nombre del grupo no puede estar vacío. Introduzca un nombre antes de crear.",
            "pt": "O nome do grupo não pode ficar vazio. Insira um nome antes de criar.",
            "fr": "Le nom du groupe ne peut pas être vide. Saisissez un nom avant de créer.",
            "ar": "لا يمكن أن يكون اسم المجموعة فارغًا. يرجى إدخال اسم قبل الإنشاء.",
            "hi": "समूह का नाम खाली नहीं हो सकता। बनाने से पहले एक नाम दर्ज करें।",
            "ta": "குழுவின் பெயர் காலியாக இருக்க முடியாது. உருவாக்குவதற்கு முன் ஒரு பெயரை உள்ளிடவும்.",
        },
    ),
    "Household name does not match. Please enter it again.": (
        "Group name does not match. Please enter it again.",
        {
            "en": "Group name does not match. Please enter it again.",
            "zh-Hans": "群组名称不匹配，请重新输入。",
            "zh-Hant": "群組名稱不符，請重新輸入。",
            "es": "El nombre del grupo no coincide. Vuelva a introducirlo.",
            "pt": "O nome do grupo não confere. Digite novamente.",
            "fr": "Le nom du groupe ne correspond pas. Veuillez le saisir à nouveau.",
            "ar": "اسم المجموعة غير متطابق. يرجى إدخاله مرة أخرى.",
            "hi": "समूह का नाम मेल नहीं खाता। कृपया इसे फिर से दर्ज करें।",
            "ta": "குழுவின் பெயர் பொருந்தவில்லை. மீண்டும் உள்ளிடவும்.",
        },
    ),
    "This household does not exist or has been deleted. Please refresh and try again.": (
        "This group does not exist or has been deleted. Please refresh and try again.",
        {
            "en": "This group does not exist or has been deleted. Please refresh and try again.",
            "zh-Hans": "该群组不存在或已被删除，请刷新后重试。",
            "zh-Hant": "該群組不存在或已被刪除，請刷新後重試。",
            "es": "Este grupo no existe o ha sido eliminado. Actualice e inténtelo de nuevo.",
            "pt": "Este grupo não existe ou foi excluído. Atualize e tente novamente.",
            "fr": "Ce groupe n'existe pas ou a été supprimé. Actualisez et réessayez.",
            "ar": "هذه المجموعة غير موجودة أو تم حذفها. يرجى التحديث والمحاولة مرة أخرى.",
            "hi": "यह समूह मौजूद नहीं है या हटा दिया गया है। कृपया ताज़ा करें और पुनः प्रयास करें।",
            "ta": "இந்த குழு இல்லை அல்லது நீக்கப்பட்டுள்ளது. புதுப்பித்து மீண்டும் முயற்சிக்கவும்.",
        },
    ),
    "This household does not exist or has been deleted.": (
        "This group does not exist or has been deleted.",
        {
            "en": "This group does not exist or has been deleted.",
            "zh-Hans": "该群组不存在或已被删除。",
            "zh-Hant": "該群組不存在或已被刪除。",
            "es": "Este grupo no existe o ha sido eliminado.",
            "pt": "Este grupo não existe ou foi excluído.",
            "fr": "Ce groupe n'existe pas ou a été supprimé.",
            "ar": "هذه المجموعة غير موجودة أو تم حذفها.",
            "hi": "यह समूह मौजूद नहीं है या हटा दिया गया है।",
            "ta": "இந்த குழு இல்லை அல்லது நீக்கப்பட்டுள்ளது.",
        },
    ),
    "You are already a member of this household.": (
        "You are already a member of this group.",
        {
            "en": "You are already a member of this group.",
            "zh-Hans": "您已经加入了该群组，无需重复添加。",
            "zh-Hant": "您已經加入了該群組，無需重複新增。",
            "es": "Ya eres miembro de este grupo.",
            "pt": "Você já é membro deste grupo.",
            "fr": "Vous êtes déjà membre de ce groupe.",
            "ar": "أنت بالفعل عضو في هذه المجموعة.",
            "hi": "आप पहले से ही इस समूह के सदस्य हैं।",
            "ta": "நீங்கள் ஏற்கனவே இந்த குழுவின் உறுப்பினர்.",
        },
    ),
    "Only the creator can disband this household.": (
        "Only the creator can disband this group.",
        {
            "en": "Only the creator can disband this group.",
            "zh-Hans": "只有创建者才能解散该群组。",
            "zh-Hant": "只有建立者才能解散該群組。",
            "es": "Solo el creador puede disolver este grupo.",
            "pt": "Somente o criador pode dissolver este grupo.",
            "fr": "Seul le créateur peut dissoudre ce groupe.",
            "ar": "يمكن للمنشئ فقط حل هذه المجموعة.",
            "hi": "केवल निर्माता ही इस समूह को भंग कर सकता है।",
            "ta": "உருவாக்குநர் மட்டுமே இந்த குழுவை கலைக்க முடியும்.",
        },
    ),
    "You are the creator of this household. Transfer ownership or disband the household before leaving.": (
        "You are the creator of this group. Transfer ownership or disband the group before leaving.",
        {
            "en": "You are the creator of this group. Transfer ownership or disband the group before leaving.",
            "zh-Hans": "您是此群组的创建者。退出前请先转移所有权或解散群组。",
            "zh-Hant": "您是此群組的建立者。退出前請先轉移所有權或解散群組。",
            "es": "Eres el creador de este grupo. Transfiere la propiedad o disuelve el grupo antes de salir.",
            "pt": "Você é o criador deste grupo. Transfira a propriedade ou dissolva o grupo antes de sair.",
            "fr": "Vous êtes le créateur de ce groupe. Transférez la propriété ou dissolvez le groupe avant de partir.",
            "ar": "أنت منشئ هذه المجموعة. انقل الملكية أو قم بحل المجموعة قبل المغادرة.",
            "hi": "आप इस समूह के निर्माता हैं। छोड़ने से पहले स्वामित्व स्थानांतरित करें या समूह भंग करें।",
            "ta": "நீங்கள் இந்த குழுவின் உருவாக்குநர். வெளியேறுவதற்கு முன் உரிமையை மாற்றவும் அல்லது குழுவை கலைக்கவும்.",
        },
    ),
    "Are you sure you want to leave this household?": (
        "Are you sure you want to leave this group?",
        {
            "en": "Are you sure you want to leave this group?",
            "zh-Hans": "确定要退出该群组吗？",
            "zh-Hant": "確定要退出該群組嗎？",
            "es": "¿Está seguro de que desea salir de este grupo?",
            "pt": "Tem certeza de que deseja sair deste grupo?",
            "fr": "Voulez-vous vraiment quitter ce groupe ?",
            "ar": "هل أنت متأكد أنك تريد مغادرة هذه المجموعة؟",
            "hi": "क्या आप वाकई इस समूह को छोड़ना चाहते हैं?",
            "ta": "இந்த குழுவை விட்டு வெளியேற விரும்புகிறீர்களா?",
        },
    ),
    "Leave Household": (
        "Leave Group",
        {
            "en": "Leave Group",
            "zh-Hans": "退出群组",
            "zh-Hant": "退出群組",
            "es": "Salir del grupo",
            "pt": "Sair do grupo",
            "fr": "Quitter le groupe",
            "ar": "مغادرة المجموعة",
            "hi": "समूह छोड़ें",
            "ta": "குழுவை விட்டு வெளியேறு",
        },
    ),
    "Could not leave household": (
        "Could not leave group",
        {
            "en": "Could not leave group",
            "zh-Hans": "退出群组失败",
            "zh-Hant": "退出群組失敗",
            "es": "No se pudo salir del grupo",
            "pt": "Não foi possível sair do grupo",
            "fr": "Impossible de quitter le groupe",
            "ar": "تعذر مغادرة المجموعة",
            "hi": "समूह छोड़ नहीं सके",
            "ta": "குழுவை விட்டு வெளியேற முடியவில்லை",
        },
    ),
    "Could not leave the household. Please try again later.": (
        "Could not leave the group. Please try again later.",
        {
            "en": "Could not leave the group. Please try again later.",
            "zh-Hans": "退出群组失败，请稍后重试。",
            "zh-Hant": "退出群組失敗，請稍後重試。",
            "es": "No se pudo salir del grupo. Inténtelo de nuevo más tarde.",
            "pt": "Não foi possível sair do grupo. Tente novamente mais tarde.",
            "fr": "Impossible de quitter le groupe. Veuillez réessayer plus tard.",
            "ar": "تعذر مغادرة المجموعة. يرجى المحاولة لاحقًا.",
            "hi": "समूह छोड़ नहीं सके। कृपया बाद में पुनः प्रयास करें।",
            "ta": "குழுவை விட்டு வெளியேற முடியவில்லை. பிறகு மீண்டும் முயற்சிக்கவும்.",
        },
    ),
    "After leaving, you won't be able to view tasks and messages in this household.": (
        "After leaving, you won't be able to view tasks and messages in this group.",
        {
            "en": "After leaving, you won't be able to view tasks and messages in this group.",
            "zh-Hans": "退出后您将无法查看群内的任务和消息。",
            "zh-Hant": "退出後您將無法查看群內的任務和訊息。",
            "es": "Después de salir, no podrá ver las tareas ni los mensajes de este grupo.",
            "pt": "Depois de sair, você não poderá ver as tarefas e mensagens deste grupo.",
            "fr": "Après votre départ, vous ne pourrez plus afficher les tâches et les messages de ce groupe.",
            "ar": "بعد المغادرة، لن تتمكن من عرض المهام والرسائل في هذه المجموعة.",
            "hi": "छोड़ने के बाद, आप इस समूह के कार्य और संदेश नहीं देख पाएंगे।",
            "ta": "வெளியேறிய பிறகு, இந்த குழுவில் உள்ள பணிகளையும் செய்திகளையும் உங்களால் பார்க்க முடியாது.",
        },
    ),
    "Disband Household": (
        "Disband Group",
        {
            "en": "Disband Group",
            "zh-Hans": "解散群组",
            "zh-Hant": "解散群組",
            "es": "Disolver grupo",
            "pt": "Dissolver grupo",
            "fr": "Dissoudre le groupe",
            "ar": "حل المجموعة",
            "hi": "समूह भंग करें",
            "ta": "குழுவை கலை",
        },
    ),
    "Enjoy your family time, or plan something new.": (
        "Enjoy your time together, or plan something new.",
        {
            "en": "Enjoy your time together, or plan something new.",
            "zh-Hans": "享受共同时光，或者计划一些新的事情。",
            "zh-Hant": "享受共同時光，或者計畫一些新的事情。",
            "es": "Disfruta del tiempo juntos o planea algo nuevo.",
            "pt": "Aproveite o tempo juntos ou planeje algo novo.",
            "fr": "Profitez de votre temps ensemble ou planifiez quelque chose de nouveau.",
            "ar": "استمتع بوقتكم معًا أو خطط لشيء جديد.",
            "hi": "एक साथ समय का आनंद लें, या कुछ नया योजना बनाएं।",
            "ta": "ஒன்றாக நேரத்தை அனுபவிக்கவும், அல்லது புதியதை திட்டமிடவும்.",
        },
    ),
    "Family Dinner": (
        "Dinner Together",
        {
            "en": "Dinner Together",
            "zh-Hans": "一起晚餐",
            "zh-Hant": "一起晚餐",
            "es": "Cena juntos",
            "pt": "Jantar juntos",
            "fr": "Dîner ensemble",
            "ar": "عشاء معًا",
            "hi": "साथ में रात्रिभोज",
            "ta": "ஒன்றாக இரவு உணவு",
        },
    ),
}

IN_PLACE_UPDATES: dict[str, dict[str, str]] = {
    "WeFamily": {
        "zh-Hans": "家音",
        "zh-Hant": "家音",
    },
}


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]

    migrated = 0
    for old_key, (new_key, translations) in KEY_MIGRATIONS.items():
        if old_key in strings:
            del strings[old_key]
        strings[new_key] = make_entry(translations)
        migrated += 1
        print(f"migrated: {old_key!r} -> {new_key!r}")

    for key, locale_updates in IN_PLACE_UPDATES.items():
        if key not in strings:
            continue
        entry = strings[key]
        localizations = entry.setdefault("localizations", {})
        for locale, value in locale_updates.items():
            localizations[locale] = make_unit(value)
        print(f"updated in-place: {key!r}")

    remaining = []
    for key, entry in strings.items():
        locs = entry.get("localizations", {})
        for locale, unit in locs.items():
            value = unit.get("stringUnit", {}).get("value", "")
            if "家庭" in value or "我們家" in value or "我们家" in value:
                remaining.append((key, locale, value))

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"\nDone. Migrated {migrated} keys.")
    if remaining:
        print("Remaining 家庭-related strings:")
        for item in remaining:
            print(f"  {item}")
    else:
        print("No remaining 家庭-related user strings in localizations.")


if __name__ == "__main__":
    main()
