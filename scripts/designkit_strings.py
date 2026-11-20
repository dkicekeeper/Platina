#!/usr/bin/env python3
"""Puts DesignKit's string keys into Platina's string catalog, in Russian and English.

DesignKit ships no strings: its components look their keys up in the app's main bundle
(DesignKit docs/localization-keys.md). Run this after moving the DesignKit pin when the new
version adds keys:

    python3 scripts/designkit_strings.py \
        --designkit ../DesignKit \
        --ru ../Dalada/ios/Dalada/Localizable.xcstrings \
        --ru ../Tenra/Tenra/ru.lproj/Localizable.strings

English comes from the Gallery's catalog in the DesignKit checkout, Russian from the given
catalogs or .strings files (Dalada's and Tenra's), then from RU_OVERRIDES below. Only entries
marked "DesignKit" are written; the app's own strings stay as they are.
"""
import argparse
import json
import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "ios/Platina/Localizable.xcstrings"
COMMENT = "DesignKit"

# Keys neither Dalada nor Tenra translate yet.
RU_OVERRIDES = {
    "checklist.complete": "Готово",
    "checklist.progress %lld %lld": "%1$lld из %2$lld",
    "common.hide": "Скрыть",
    "common.locked": "Закрыто",
    "download.pause": "Пауза",
    "download.start": "Скачать",
    "iconStyle.tint.inherit": "Цвет текста",
    "infoTip.about": "Подробнее: %@",
    "infoTip.label": "Подробнее",
    "message.read": "Прочитано",
    "message.sending": "Отправляется…",
    "message.sent": "Отправлено",
    "picker.create": "Создать «%@»",
    "picker.noResults": "Ничего не найдено",
    "picker.search": "Поиск",
    "thumbnail.saved": "Сохранено",
    "thumbnail.verified": "Проверено",
}


def designkit_keys(designkit: Path) -> list[str]:
    keys = []
    for line in (designkit / "docs/localization-keys.md").read_text(encoding="utf-8").splitlines():
        match = re.match(r"\| `([^`]+)` \|", line)
        if match:
            keys.append(match.group(1))
    return keys


def catalog_values(path: Path, language: str) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    values = {}
    for key, entry in data.get("strings", {}).items():
        unit = entry.get("localizations", {}).get(language, {}).get("stringUnit")
        if unit and unit.get("value"):
            values[key] = unit["value"]
    return values


def strings_file_values(path: Path) -> dict[str, str]:
    values = {}
    pattern = re.compile(r'\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values[match.group(1)] = match.group(2).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--designkit", type=Path, required=True)
    parser.add_argument("--ru", type=Path, action="append", default=[])
    args = parser.parse_args()

    keys = designkit_keys(args.designkit)
    english = catalog_values(args.designkit / "Gallery/Gallery/Localizable.xcstrings", "en")
    russian: dict[str, str] = {}
    for source in args.ru:
        found = catalog_values(source, "ru") if source.suffix == ".xcstrings" else strings_file_values(source)
        for key, value in found.items():
            russian.setdefault(key, value)
    russian.update({k: v for k, v in RU_OVERRIDES.items() if k not in russian})

    catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {
        "sourceLanguage": "ru", "strings": {}, "version": "1.0",
    }
    strings = catalog["strings"]
    missing = []
    for key in keys:
        existing = strings.get(key)
        if existing and existing.get("comment") != COMMENT:
            continue  # the app translated it its own way
        en, ru = english.get(key), russian.get(key)
        if not en or not ru:
            missing.append(key)
            continue
        strings[key] = {
            "comment": COMMENT,
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "ru": {"stringUnit": {"state": "translated", "value": ru}},
            },
        }
    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(keys) - len(missing)} DesignKit keys in {CATALOG.name}")
    if missing:
        print("No translation for:", ", ".join(missing), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
