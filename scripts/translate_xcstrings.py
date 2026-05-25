#!/usr/bin/env python3
"""Auto-translate Localizable.xcstrings using Google Translate."""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"

TARGET_LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]

GOOGLE_LOCALE = {
    "en": "en",
    "zh-Hans": "zh-CN",
    "zh-Hant": "zh-TW",
    "es": "es",
    "pt": "pt",
    "ar": "ar",
    "hi": "hi",
    "fr": "fr",
    "ta": "ta",
}

SKIP_KEYS = {"", "0", "—", "˄", "˅", "SIG"}

FORMAT_TOKEN_PATTERN = re.compile(
    r"(%(?:@|\d*\$@|\d*\$lld|\d*\$d|\d*\$f|\d*\$s|lld|d|f|s|%))"
)

CJK_PATTERN = re.compile(r"[\u4e00-\u9fff\u3400-\u4dbf]")


def log(message: str) -> None:
    print(message, flush=True)


def detect_source_locale(text: str) -> str:
    return "zh-CN" if CJK_PATTERN.search(text) else "en"


def protect_format_tokens(text: str) -> tuple[str, list[str]]:
    tokens: list[str] = []

    def repl(match: re.Match[str]) -> str:
        tokens.append(match.group(0))
        return f"XFM{len(tokens) - 1}X"

    return FORMAT_TOKEN_PATTERN.sub(repl, text), tokens


def restore_format_tokens(text: str, tokens: list[str]) -> str:
    for index, token in enumerate(tokens):
        for candidate in (
            f"XFM{index}X",
            f"XFM {index} X",
            f"X FM {index} X",
        ):
            text = text.replace(candidate, token)
    return text


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


class TranslatorPool:
    def __init__(self) -> None:
        self.cache: dict[tuple[str, str, str], str] = {}
        self.translators: dict[tuple[str, str], GoogleTranslator] = {}

    def translate(self, text: str, source: str, target: str) -> str:
        if source == target:
            return text

        key = (text, source, target)
        if key in self.cache:
            return self.cache[key]

        pool_key = (source, target)
        if pool_key not in self.translators:
            self.translators[pool_key] = GoogleTranslator(source=source, target=target)

        protected, tokens = protect_format_tokens(text)
        try:
            translated = self.translators[pool_key].translate(protected)
        except Exception as error:  # noqa: BLE001
            log(f"  ! failed ({source}->{target}) {text!r}: {error}")
            translated = text

        translated = restore_format_tokens(translated, tokens)
        self.cache[key] = translated
        return translated


def is_fully_translated(entry: dict) -> bool:
    localizations = entry.get("localizations", {})
    return all(locale in localizations for locale in TARGET_LOCALES)


def build_localizations(key: str, pool: TranslatorPool) -> dict[str, dict]:
    if key in SKIP_KEYS:
        return {locale: make_unit(key) for locale in TARGET_LOCALES}

    source = detect_source_locale(key)
    localizations: dict[str, dict] = {}

    for locale in TARGET_LOCALES:
        google_target = GOOGLE_LOCALE[locale]
        if locale == "en" and source == "en":
            value = key
        elif locale == "zh-Hans" and source == "zh-CN":
            value = key
        else:
            value = pool.translate(key, source, google_target)
        localizations[locale] = make_unit(value)

    return localizations


def save(data: dict) -> None:
    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings: dict[str, dict] = data.get("strings", {})
    pool = TranslatorPool()

    total = len(strings)
    updated = 0

    for index, (key, entry) in enumerate(strings.items(), start=1):
        if is_fully_translated(entry):
            continue

        preview = key.replace("\n", "\\n")
        if len(preview) > 56:
            preview = preview[:56] + "…"
        log(f"[{index}/{total}] {preview}")

        entry["localizations"] = build_localizations(key, pool)
        updated += 1

        if updated % 10 == 0:
            save(data)
            log(f"  checkpoint saved ({updated} updated)")

    data["strings"] = strings
    save(data)
    log(f"\nDone. Updated {updated} of {total} strings.")


if __name__ == "__main__":
    main()
