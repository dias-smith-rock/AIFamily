#!/usr/bin/env python3
"""Normalize product naming: zh=家音, en/other=WeFamily."""

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


KEY_MIGRATIONS: dict[str, tuple[str, dict[str, str]]] = {
    "About AIFamily": (
        "About WeFamily",
        {
            "en": "About WeFamily",
            "zh-Hans": "关于家音",
            "zh-Hant": "關於家音",
            "es": "Acerca de WeFamily",
            "pt": "Sobre WeFamily",
            "fr": "À propos de WeFamily",
            "ar": "حول WeFamily",
            "hi": "WeFamily के बारे में",
            "ta": "WeFamily பற்றி",
        },
    ),
}

IN_PLACE: dict[str, dict[str, str]] = {
    "WeFamily": {
        "en": "WeFamily",
        "zh-Hans": "家音",
        "zh-Hant": "家音",
        "es": "WeFamily",
        "pt": "WeFamily",
        "fr": "WeFamily",
        "ar": "WeFamily",
        "hi": "WeFamily",
        "ta": "WeFamily",
    },
    "欢迎来到 WeFamily": {
        "en": "Welcome to WeFamily",
        "zh-Hans": "欢迎来到家音",
        "zh-Hant": "歡迎來到家音",
        "es": "Bienvenido a WeFamily",
        "pt": "Bem-vindo à WeFamily",
        "fr": "Bienvenue sur WeFamily",
        "ar": "مرحبًا بك في WeFamily",
        "hi": "WeFamily में आपका स्वागत है",
        "ta": "WeFamilyக்கு வரவேற்கிறோம்",
    },
    "Ask the other party to use the WeFamily App to scan the code, or enter the invitation code below to join.": {
        "en": "Ask the other party to use the WeFamily App to scan the code, or enter the invitation code below to join.",
        "zh-Hans": "让对方使用家音 App 扫码，或输入下方邀请码即可加入。",
        "zh-Hant": "請對方使用家音 App 掃碼，或輸入下方邀請碼即可加入。",
        "es": "Pídale a la otra parte que use la aplicación WeFamily para escanear el código o ingrese el código de invitación a continuación para unirse.",
        "pt": "Peça à outra parte para usar o aplicativo WeFamily para escanear o código ou insira o código de convite abaixo para participar.",
        "fr": "Demandez à l'autre partie d'utiliser l'application WeFamily pour scanner le code, ou entrez le code d'invitation ci-dessous pour vous joindre.",
        "ar": "اطلب من الطرف الآخر استخدام تطبيق WeFamily لمسح الرمز ضوئيًا، أو إدخال رمز الدعوة أدناه للانضمام.",
        "hi": "दूसरे पक्ष से कोड स्कैन करने के लिए WeFamily ऐप का उपयोग करने के लिए कहें, या शामिल होने के लिए नीचे निमंत्रण कोड दर्ज करें।",
        "ta": "குறியீட்டை ஸ்கேன் செய்ய WeFamily ஆப்ஸைப் பயன்படுத்தும்படி மற்ற தரப்பினரிடம் கேட்கவும் அல்லது சேர்வதற்கு கீழே உள்ள அழைப்புக் குறியீட்டை உள்ளிடவும்.",
    },
}

NEW_KEYS: dict[str, dict[str, str]] = {
    "You're invited to join a WeFamily group! Copy this invite code: %1$@, or scan the QR code in the app.": {
        "en": "You're invited to join a WeFamily group! Copy this invite code: %1$@, or scan the QR code in the app.",
        "zh-Hans": "邀请你加入家音群组空间！请复制此邀请码：%1$@，或使用 App 扫码加入。",
        "zh-Hant": "邀請你加入家音群組空間！請複製此邀請碼：%1$@，或使用 App 掃碼加入。",
        "es": "¡Te invitan a unirte a un grupo de WeFamily! Copia este código de invitación: %1$@, o escanea el código QR en la app.",
        "pt": "Você foi convidado a entrar em um grupo WeFamily! Copie este código de convite: %1$@, ou escaneie o QR code no app.",
        "fr": "Vous êtes invité à rejoindre un groupe WeFamily ! Copiez ce code d'invitation : %1$@, ou scannez le QR code dans l'app.",
        "ar": "أنت مدعو للانضمام إلى مجموعة WeFamily! انسخ رمز الدعوة: %1$@، أو امسح رمز QR في التطبيق.",
        "hi": "आपको WeFamily समूह में शामिल होने के लिए आमंत्रित किया गया है! यह निमंत्रण कोड कॉपी करें: %1$@, या ऐप में QR कोड स्कैन करें।",
        "ta": "WeFamily குழுவில் சேர அழைக்கப்பட்டுள்ளீர்கள்! இந்த அழைப்புக் குறியீட்டை நகலெடுக்கவும்: %1$@, அல்லது ஆப்ஸில் QR குறியீட்டை ஸ்கேன் செய்யவும்.",
    },
}

REMOVE_KEYS = [
    "让对方使用 WeFamily App 扫码，或输入下方邀请码即可加入。",
]


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]

    for old_key, (new_key, translations) in KEY_MIGRATIONS.items():
        if old_key in strings:
            del strings[old_key]
        strings[new_key] = make_entry(translations)
        print(f"migrated: {old_key!r} -> {new_key!r}")

    for key, locale_updates in IN_PLACE.items():
        if key not in strings:
            strings[key] = make_entry(locale_updates)
        else:
            localizations = strings[key].setdefault("localizations", {})
            for locale, value in locale_updates.items():
                localizations[locale] = make_unit(value)
        print(f"updated: {key!r}")

    for key, translations in NEW_KEYS.items():
        strings[key] = make_entry(translations)
        print(f"added: {key!r}")

    for key in REMOVE_KEYS:
        if key in strings:
            del strings[key]
            print(f"removed stale key: {key!r}")

    bad = []
    for key, entry in strings.items():
        for locale, unit in entry.get("localizations", {}).items():
            value = unit.get("stringUnit", {}).get("value", "")
            if any(token in value for token in ("AIFamily", "爱家", "愛家", "Nosotros, familia", "NousFamille", "NósFamília")):
                bad.append((key, locale, value))

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if bad:
        print("\nRemaining suspicious product names:")
        for item in bad:
            print(f"  {item}")
    else:
        print("\nNo remaining AIFamily/爱家 variants in localizations.")


if __name__ == "__main__":
    main()
