#!/usr/bin/env python3
"""Fill empty or incomplete entries in reminder/Localizable.xcstrings."""

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


# Keys with empty `localizations` — full 9-locale translations
NEW_TRANSLATIONS: dict[str, dict[str, str]] = {
    "已锁定": {
        "en": "Locked",
        "zh-Hans": "已锁定",
        "zh-Hant": "已鎖定",
        "es": "Bloqueado",
        "pt": "Bloqueado",
        "ar": "مقفل",
        "hi": "लॉक किया गया",
        "fr": "Verrouillé",
        "ta": "பூட்டப்பட்டது",
    },
    "稍后": {
        "en": "Later",
        "zh-Hans": "稍后",
        "zh-Hant": "稍後",
        "es": "Más tarde",
        "pt": "Mais tarde",
        "ar": "لاحقًا",
        "hi": "बाद में",
        "fr": "Plus tard",
        "ta": "பிறகு",
    },
    "确定": {
        "en": "OK",
        "zh-Hans": "确定",
        "zh-Hant": "確定",
        "es": "Aceptar",
        "pt": "OK",
        "ar": "موافق",
        "hi": "ठीक",
        "fr": "OK",
        "ta": "சரி",
    },
    "Pro": {
        "en": "Pro",
        "zh-Hans": "Pro",
        "zh-Hant": "Pro",
        "es": "Pro",
        "pt": "Pro",
        "ar": "Pro",
        "hi": "Pro",
        "fr": "Pro",
        "ta": "Pro",
    },
    "暂无其他成员": {
        "en": "No other members yet",
        "zh-Hans": "暂无其他成员",
        "zh-Hant": "暫無其他成員",
        "es": "Aún no hay otros miembros",
        "pt": "Ainda não há outros membros",
        "ar": "لا يوجد أعضاء آخرون بعد",
        "hi": "अभी कोई अन्य सदस्य नहीं",
        "fr": "Pas encore d'autres membres",
        "ta": "வேறு உறுப்பினர்கள் இல்லை",
    },
    "未知群组": {
        "en": "Unknown group",
        "zh-Hans": "未知群组",
        "zh-Hant": "未知群組",
        "es": "Grupo desconocido",
        "pt": "Grupo desconhecido",
        "ar": "مجموعة غير معروفة",
        "hi": "अज्ञात समूह",
        "fr": "Groupe inconnu",
        "ta": "அறியப்படாத குழு",
    },
    "请输入群组名称。": {
        "en": "Please enter a group name.",
        "zh-Hans": "请输入群组名称。",
        "zh-Hant": "請輸入群組名稱。",
        "es": "Introduce un nombre de grupo.",
        "pt": "Introduza o nome do grupo.",
        "ar": "يرجى إدخال اسم المجموعة.",
        "hi": "कृपया समूह का नाम दर्ज करें।",
        "fr": "Veuillez saisir un nom de groupe.",
        "ta": "குழுப் பெயரை உள்ளிடவும்.",
    },
    "群组名称不能为空。": {
        "en": "Group name cannot be empty.",
        "zh-Hans": "群组名称不能为空。",
        "zh-Hant": "群組名稱不能為空。",
        "es": "El nombre del grupo no puede estar vacío.",
        "pt": "O nome do grupo não pode estar vazio.",
        "ar": "لا يمكن أن يكون اسم المجموعة فارغًا.",
        "hi": "समूह का नाम खाली नहीं हो सकता।",
        "fr": "Le nom du groupe ne peut pas être vide.",
        "ta": "குழுப் பெயர் காலியாக இருக்க முடியாது.",
    },
    "该群组名称已被占用，请换一个名称。": {
        "en": "This group name is already taken. Please choose another.",
        "zh-Hans": "该群组名称已被占用，请换一个名称。",
        "zh-Hant": "該群組名稱已被使用，請換一個名稱。",
        "es": "Este nombre de grupo ya está en uso. Elige otro.",
        "pt": "Este nome de grupo já está em uso. Escolha outro.",
        "ar": "اسم المجموعة مستخدم بالفعل. يرجى اختيار اسم آخر.",
        "hi": "यह समूह नाम पहले से लिया गया है। कृपया दूसरा नाम चुनें।",
        "fr": "Ce nom de groupe est déjà pris. Veuillez en choisir un autre.",
        "ta": "இந்த குழுப் பெயர் ஏற்கனவே உள்ளது. வேறு பெயரைத் தேர்ந்தெடுக்கவும்.",
    },
    "仅创建者或管理员可以修改群组名称。": {
        "en": "Only the creator or an admin can rename the group.",
        "zh-Hans": "仅创建者或管理员可以修改群组名称。",
        "zh-Hant": "僅建立者或管理員可以修改群組名稱。",
        "es": "Solo el creador o un administrador puede cambiar el nombre del grupo.",
        "pt": "Apenas o criador ou um administrador pode alterar o nome do grupo.",
        "ar": "يمكن للمنشئ أو المسؤول فقط تغيير اسم المجموعة.",
        "hi": "केवल निर्माता या व्यवस्थापक समूह का नाम बदल सकते हैं।",
        "fr": "Seul le créateur ou un administrateur peut renommer le groupe.",
        "ta": "உருவாக்குபவர் அல்லது நிர்வாகி மட்டுமே குழுப் பெயரை மாற்ற முடியும்.",
    },
    "重命名群组失败，请稍后重试。": {
        "en": "Failed to rename the group. Please try again later.",
        "zh-Hans": "重命名群组失败，请稍后重试。",
        "zh-Hant": "重新命名群組失敗，請稍後重試。",
        "es": "No se pudo cambiar el nombre del grupo. Inténtalo más tarde.",
        "pt": "Falha ao renomear o grupo. Tente novamente mais tarde.",
        "ar": "فشل إعادة تسمية المجموعة. يرجى المحاولة لاحقًا.",
        "hi": "समूह का नाम बदलने में विफल। कृपया बाद में पुनः प्रयास करें।",
        "fr": "Échec du renommage du groupe. Veuillez réessayer plus tard.",
        "ta": "குழுப் பெயர் மாற்றம் தோல்வி. பிறகு மீண்டும் முயற்சிக்கவும்.",
    },
    "任务数据组装失败，请重试。": {
        "en": "Failed to prepare task data. Please try again.",
        "zh-Hans": "任务数据组装失败，请重试。",
        "zh-Hant": "任務資料組裝失敗，請重試。",
        "es": "Error al preparar los datos de la tarea. Inténtalo de nuevo.",
        "pt": "Falha ao preparar os dados da tarefa. Tente novamente.",
        "ar": "فشل إعداد بيانات المهمة. يرجى المحاولة مرة أخرى.",
        "hi": "कार्य डेटा तैयार करने में विफल। कृपया पुनः प्रयास करें।",
        "fr": "Échec de la préparation des données de tâche. Veuillez réessayer.",
        "ta": "பணி தரவு தயாரிப்பு தோல்வி. மீண்டும் முயற்சிக்கவும்.",
    },
    "附件上传失败，请稍后重试。": {
        "en": "Attachment upload failed. Please try again later.",
        "zh-Hans": "附件上传失败，请稍后重试。",
        "zh-Hant": "附件上傳失敗，請稍後重試。",
        "es": "Error al subir el adjunto. Inténtalo más tarde.",
        "pt": "Falha no envio do anexo. Tente novamente mais tarde.",
        "ar": "فشل رفع المرفق. يرجى المحاولة لاحقًا.",
        "hi": "अटैचमेंट अपलोड विफल। कृपया बाद में पुनः प्रयास करें।",
        "fr": "Échec du téléversement de la pièce jointe. Veuillez réessayer plus tard.",
        "ta": "இணைப்பு பதிவேற்றம் தோல்வி. பிறகு மீண்டும் முயற்சிக்கவும்.",
    },
    "请验证身份以访问同圈中的家庭日程与任务。": {
        "en": "Verify your identity to access family schedules and tasks in WeSync.",
        "zh-Hans": "请验证身份以访问同圈中的家庭日程与任务。",
        "zh-Hant": "請驗證身分以存取同圈中的家庭日程與任務。",
        "es": "Verifica tu identidad para acceder a los horarios y tareas familiares en WeSync.",
        "pt": "Verifique sua identidade para acessar horários e tarefas da família no WeSync.",
        "ar": "تحقق من هويتك للوصول إلى جداول ومهام العائلة في WeSync.",
        "hi": "WeSync में परिवार के शेड्यूल और कार्यों तक पहुँचने के लिए अपनी पहचान सत्यापित करें।",
        "fr": "Vérifiez votre identité pour accéder aux plannings et tâches familiales dans WeSync.",
        "ta": "WeSync இல் குடும்ப அட்டவணை மற்றும் பணிகளை அணுக உங்கள் அடையாளத்தை சரிபார்க்கவும்.",
    },
    "轻点以切换群组": {
        "en": "Double-tap to switch group",
        "zh-Hans": "轻点以切换群组",
        "zh-Hant": "輕點以切換群組",
        "es": "Toca para cambiar de grupo",
        "pt": "Toque para mudar de grupo",
        "ar": "انقر للتبديل بين المجموعات",
        "hi": "समूह बदलने के लिए टैप करें",
        "fr": "Appuyez pour changer de groupe",
        "ta": "குழுவை மாற்ற தட்டவும்",
    },
    "群组，%@": {
        "en": "Group, %@",
        "zh-Hans": "群组，%@",
        "zh-Hant": "群組，%@",
        "es": "Grupo, %@",
        "pt": "Grupo, %@",
        "ar": "المجموعة، %@",
        "hi": "समूह, %@",
        "fr": "Groupe, %@",
        "ta": "குழு, %@",
    },
    "此日程由外部同步，暂不支持在应用内修改": {
        "en": "This event was synced from an external calendar and cannot be edited in the app.",
        "zh-Hans": "此日程由外部同步，暂不支持在应用内修改",
        "zh-Hant": "此日程由外部同步，暫不支援在應用程式內修改",
        "es": "Este evento se sincronizó desde un calendario externo y no se puede editar en la app.",
        "pt": "Este evento foi sincronizado de um calendário externo e não pode ser editado no app.",
        "ar": "تمت مزامنة هذا الحدث من تقويم خارجي ولا يمكن تعديله في التطبيق.",
        "hi": "यह इवेंट बाहरी कैलेंडर से सिंक किया गया था और ऐप में संपादित नहीं किया जा सकता।",
        "fr": "Cet événement a été synchronisé depuis un calendrier externe et ne peut pas être modifié dans l'app.",
        "ta": "இந்த நிகழ்வு வெளி காலெண்டரிலிருந்து ஒத்திசைக்கப்பட்டது; பயன்பாட்டில் திருத்த முடியாது.",
    },
    "喜欢同圈吗？": {
        "en": "Enjoying WeSync?",
        "zh-Hans": "喜欢同圈吗？",
        "zh-Hant": "喜歡同圈嗎？",
        "es": "¿Te gusta WeSync?",
        "pt": "Está a gostar do WeSync?",
        "ar": "هل تستمتع بـ WeSync؟",
        "hi": "WeSync पसंद आ रहा है?",
        "fr": "Vous aimez WeSync ?",
        "ta": "WeSync பிடிக்கிறதா?",
    },
    "以后再说": {
        "en": "Maybe Later",
        "zh-Hans": "以后再说",
        "zh-Hant": "以後再說",
        "es": "Más tarde",
        "pt": "Mais tarde",
        "ar": "لاحقًا",
        "hi": "बाद में",
        "fr": "Plus tard",
        "ta": "பிறகு",
    },
    "去评分": {
        "en": "Write a Review",
        "zh-Hans": "去评分",
        "zh-Hant": "去評分",
        "es": "Escribir reseña",
        "pt": "Avaliar na App Store",
        "ar": "كتابة تقييم",
        "hi": "समीक्षा लिखें",
        "fr": "Laisser un avis",
        "ta": "மதிப்புரை எழுதுங்கள்",
    },
    "您的反馈能帮助我们为家庭和团队把应用做得更好。愿意花一点时间留个评价吗？": {
        "en": "Your feedback helps us improve the app for families and teams. Would you mind leaving a quick review?",
        "zh-Hans": "您的反馈能帮助我们为家庭和团队把应用做得更好。愿意花一点时间留个评价吗？",
        "zh-Hant": "您的回饋能幫助我們為家庭與團隊把應用做得更好。願意花一點時間留個評價嗎？",
        "es": "Tu opinión nos ayuda a mejorar la app para familias y equipos. ¿Podrías dejar una reseña rápida?",
        "pt": "O seu feedback ajuda-nos a melhorar a app para famílias e equipas. Pode deixar uma avaliação rápida?",
        "ar": "ملاحظاتك تساعدنا على تحسين التطبيق للعائلات والفرق. هل تود ترك تقييم سريع؟",
        "hi": "आपकी प्रतिक्रिया परिवारों और टीमों के लिए ऐप को बेहतर बनाने में मदद करती है। क्या आप एक समीक्षा छोड़ सकते हैं?",
        "fr": "Vos retours nous aident à améliorer l'app pour les familles et les équipes. Pourriez-vous laisser un avis rapide ?",
        "ta": "உங்கள் கருத்து குடும்பங்களுக்கும் குழுக்களுக்கும் செயலியை மேம்படுத்த உதவுகிறது. ஒரு மதிப்புரை விடுவீர்களா?",
    },
    "%@:": {
        "en": "%@:",
        "zh-Hans": "%@:",
        "zh-Hant": "%@:",
        "es": "%@:",
        "pt": "%@:",
        "ar": "%@:",
        "hi": "%@:",
        "fr": "%@:",
        "ta": "%@:",
    },
    "%lld": {
        "en": "%lld",
        "zh-Hans": "%lld",
        "zh-Hant": "%lld",
        "es": "%lld",
        "pt": "%lld",
        "ar": "%lld",
        "hi": "%lld",
        "fr": "%lld",
        "ta": "%lld",
    },
}

# Keys with partial locales — fill only missing
PARTIAL_TRANSLATIONS: dict[str, dict[str, str]] = {
    "图片加载中": {
        "es": "Cargando imagen",
        "pt": "A carregar imagem",
        "ar": "جارٍ تحميل الصورة",
        "hi": "छवि लोड हो रही है",
        "fr": "Chargement de l'image",
        "ta": "படம் ஏற்றப்படுகிறது",
    },
}


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]
    filled_empty = 0
    filled_partial = 0

    for key, translations in NEW_TRANSLATIONS.items():
        entry = strings.setdefault(key, {})
        locs = entry.get("localizations") or {}
        if not locs or "localizations" in locs:
            if "localizations" in locs:
                locs = locs.get("localizations") or {}
            entry["localizations"] = make_entry(translations)["localizations"]
            filled_empty += 1

    for key, extra in PARTIAL_TRANSLATIONS.items():
        entry = strings.get(key)
        if not entry:
            continue
        locs = entry.setdefault("localizations", {})
        for locale, value in extra.items():
            if locale not in locs or not locs[locale].get("stringUnit", {}).get("value"):
                locs[locale] = make_unit(value)
                filled_partial += 1

    # Remove stale English duplicate if Chinese key is now complete
    stale = "This event was synced from an external calendar and cannot be edited in the app."
    if stale in strings and "此日程由外部同步，暂不支持在应用内修改" in strings:
        chinese = strings["此日程由外部同步，暂不支持在应用内修改"]
        if chinese.get("localizations") and strings[stale].get("extractionState") == "stale":
            del strings[stale]

    # Remove obsolete English review keys after migration to Chinese
    for obsolete in (
        "Enjoying WeSync?",
        "Maybe Later",
        "Write a Review",
        "Your feedback helps us make the app even better for families and teams. Would you mind leaving a quick review?",
    ):
        if obsolete in strings:
            del strings[obsolete]

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Filled {filled_empty} empty keys; patched {filled_partial} partial locale slots.")


if __name__ == "__main__":
    main()
