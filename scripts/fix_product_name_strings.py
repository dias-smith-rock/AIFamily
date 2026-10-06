#!/usr/bin/env python3
"""Normalize product naming: zh=同圈, en/other=Family Sync."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]

OLD_ZH = "家音"
NEW_ZH = "同圈"
OLD_EN = "WeFamily"
NEW_EN = "Family Sync"


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def make_entry(translations: dict[str, str]) -> dict:
    return {"localizations": {locale: make_unit(translations[locale]) for locale in LOCALES}}


KEY_MIGRATIONS: dict[str, tuple[str, dict[str, str]]] = {
    "关于 WeFamily": (
        "关于同圈",
        {
            "en": "About Family Sync",
            "zh-Hans": "关于同圈",
            "zh-Hant": "關於同圈",
            "es": "Acerca de Family Sync",
            "pt": "Sobre Family Sync",
            "fr": "À propos de Family Sync",
            "ar": "حول Family Sync",
            "hi": "Family Sync के बारे में",
            "ta": "Family Sync பற்றி",
        },
    ),
    "欢迎来到 WeFamily": (
        "欢迎来到同圈",
        {
            "en": "Welcome to Family Sync",
            "zh-Hans": "欢迎来到同圈",
            "zh-Hant": "歡迎來到同圈",
            "es": "Bienvenido a Family Sync",
            "pt": "Bem-vindo ao Family Sync",
            "fr": "Bienvenue sur Family Sync",
            "ar": "مرحبًا بك في Family Sync",
            "hi": "Family Sync में आपका स्वागत है",
            "ta": "Family Syncக்கு வரவேற்கிறோம்",
        },
    ),
    "登录 家音": (
        "登录同圈",
        {
            "en": "Sign in to Family Sync",
            "zh-Hans": "登录同圈",
            "zh-Hant": "登入同圈",
            "es": "Iniciar sesión en Family Sync",
            "pt": "Entrar no Family Sync",
            "fr": "Connexion à Family Sync",
            "ar": "تسجيل الدخول إلى Family Sync",
            "hi": "Family Sync में साइन इन करें",
            "ta": "Family Sync இல் உள்நுழைக",
        },
    ),
    "WeFamily": (
        "Family Sync",
        {
            "en": "Family Sync",
            "zh-Hans": "同圈",
            "zh-Hant": "同圈",
            "es": "Family Sync",
            "pt": "Family Sync",
            "fr": "Family Sync",
            "ar": "Family Sync",
            "hi": "Family Sync",
            "ta": "Family Sync",
        },
    ),
    "让对方使用家音 App 扫码，或输入下方邀请码即可加入。": (
        "让对方使用同圈 App 扫码，或输入下方邀请码即可加入。",
        {
            "en": "Ask the other party to use the Family Sync app to scan the code, or enter the invitation code below to join.",
            "zh-Hans": "让对方使用同圈 App 扫码，或输入下方邀请码即可加入。",
            "zh-Hant": "請對方使用同圈 App 掃碼，或輸入下方邀請碼即可加入。",
            "es": "Pídale a la otra parte que use la aplicación Family Sync para escanear el código o ingrese el código de invitación a continuación para unirse.",
            "pt": "Peça à outra parte para usar o aplicativo Family Sync para escanear o código ou insira o código de convite abaixo para participar.",
            "fr": "Demandez à l'autre partie d'utiliser l'application Family Sync pour scanner le code, ou entrez le code d'invitation ci-dessous pour vous joindre.",
            "ar": "اطلب من الطرف الآخر استخدام تطبيق Family Sync لمسح الرمز ضوئيًا، أو إدخال رمز الدعوة أدناه للانضمام.",
            "hi": "दूसरे पक्ष से कोड स्कैन करने के लिए Family Sync ऐप का उपयोग करने के लिए कहें, या शामिल होने के लिए नीचे निमंत्रण कोड दर्ज करें।",
            "ta": "குறியீட்டை ஸ்கேன் செய்ய Family Sync ஆப்ஸைப் பயன்படுத்தும்படி மற்ற தரப்பினரிடம் கேட்கவும் அல்லது சேர்வதற்கு கீழே உள்ள அழைப்புக் குறியீட்டை உள்ளிடவும்.",
        },
    ),
    "邀请你加入家音群组空间！请复制此邀请码：%1$@，或使用 App 扫码加入。": (
        "邀请你加入同圈群组空间！请复制此邀请码：%1$@，或使用 App 扫码加入。",
        {
            "en": "You're invited to join a Family Sync group! Copy this invite code: %1$@, or scan the QR code in the app.",
            "zh-Hans": "邀请你加入同圈群组空间！请复制此邀请码：%1$@，或使用 App 扫码加入。",
            "zh-Hant": "邀請你加入同圈群組空間！請複製此邀請碼：%1$@，或使用 App 掃碼加入。",
            "es": "¡Te invitan a unirte a un grupo de Family Sync! Copia este código de invitación: %1$@, o escanea el código QR en la app.",
            "pt": "Você foi convidado a entrar em um grupo Family Sync! Copie este código de convite: %1$@, ou escaneie o QR code no app.",
            "fr": "Vous êtes invité à rejoindre un groupe Family Sync ! Copiez ce code d'invitation : %1$@, ou scannez le QR code dans l'app.",
            "ar": "أنت مدعو للانضمام إلى مجموعة Family Sync! انسخ رمز الدعوة: %1$@، أو امسح رمز QR في التطبيق.",
            "hi": "आपको Family Sync समूह में शामिल होने के लिए आमंत्रित किया गया है! यह निमंत्रण कोड कॉपी करें: %1$@, या ऐप में QR कोड स्कैन करें।",
            "ta": "Family Sync குழுவில் சேர அழைக்கப்பட்டுள்ளீர்கள்! இந்த அழைப்புக் குறியீட்டை நகலெடுக்கவும்: %1$@, அல்லது ஆப்ஸில் QR குறியீட்டை ஸ்கேன் செய்யவும்.",
        },
    ),
}

REMOVE_KEYS = [
    "About WeFamily",
    "Ask the other party to use the WeFamily App to scan the code, or enter the invitation code below to join.",
    "You're invited to join a WeFamily group! Copy this invite code: %1$@, or scan the QR code in the app.",
    "让对方使用 WeFamily App 扫码，或输入下方邀请码即可加入。",
]


def replace_brand(text: str) -> str:
    return text.replace(OLD_ZH, NEW_ZH).replace(OLD_EN, NEW_EN)


def migrate_keys(strings: dict) -> None:
    for old_key, (new_key, translations) in KEY_MIGRATIONS.items():
        if old_key in strings:
            del strings[old_key]
        strings[new_key] = make_entry(translations)
        print(f"migrated: {old_key!r} -> {new_key!r}")


def sweep_values(strings: dict) -> int:
    updated = 0
    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        for locale, unit in localizations.items():
            string_unit = unit.get("stringUnit", {})
            value = string_unit.get("value", "")
            if not value:
                continue
            new_value = replace_brand(value)
            if new_value != value:
                string_unit["value"] = new_value
                updated += 1
        new_key = replace_brand(key)
        if new_key != key:
            strings[new_key] = entry
            del strings[key]
            print(f"renamed key: {key!r} -> {new_key!r}")
    return updated


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]

    migrate_keys(strings)

    for key in REMOVE_KEYS:
        if key in strings:
            del strings[key]
            print(f"removed stale key: {key!r}")

    swept = sweep_values(strings)
    print(f"swept {swept} localization value(s) for leftover brand tokens")

    bad = []
    for key, entry in strings.items():
        for locale, unit in entry.get("localizations", {}).items():
            value = unit.get("stringUnit", {}).get("value", "")
            if any(token in value for token in ("AIFamily", OLD_ZH, "愛家", OLD_EN, "爱家")):
                bad.append((key, locale, value))
        if any(token in key for token in (OLD_ZH, OLD_EN, "爱家", "愛家")):
            bad.append((key, "(key)", key))

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if bad:
        print("\nRemaining suspicious product names:")
        for item in bad:
            print(f"  {item}")
    else:
        print("\nNo remaining legacy product names in localizations.")


if __name__ == "__main__":
    main()
