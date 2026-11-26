#!/usr/bin/env python3
"""Checks the app's own interface strings against the copy rule (CLAUDE.md, «Тексты»).

Fails on a long dash (— or –) and on a string longer than MAX_LENGTH characters, in Russian or
English. DesignKit's keys (comment "DesignKit", written by scripts/designkit_strings.py) are
skipped: they come from Dalada and Tenra.

    python3 scripts/copy_lint.py
"""
import json
import sys
from pathlib import Path

CATALOGS = [Path("ios/Platina/Localizable.xcstrings"), Path("ios/Platina/AppShortcuts.xcstrings")]
MAX_LENGTH = 90


def values(unit: dict):
    """Every value of a localization: the plain one and those of its plural or device variations."""
    if "stringUnit" in unit:
        yield unit["stringUnit"].get("value", "")
    for variants in unit.get("variations", {}).values():
        for variant in variants.values():
            yield from values(variant)


def main() -> int:
    problems = []
    for catalog in CATALOGS:
        if not catalog.exists():
            continue
        strings = json.loads(catalog.read_text(encoding="utf-8"))["strings"]
        for key, entry in sorted(strings.items()):
            if "DesignKit" in (entry.get("comment") or ""):
                continue
            for language in ("ru", "en"):
                for value in values(entry.get("localizations", {}).get(language, {})):
                    if "—" in value or "–" in value:
                        problems.append(f"{catalog.name}: {key} [{language}]: a long dash: {value}")
                    if len(value) > MAX_LENGTH:
                        problems.append(f"{catalog.name}: {key} [{language}]: {len(value)} characters (at most {MAX_LENGTH}): {value}")
    for problem in problems:
        print(problem)
    if problems:
        print(f"\n{len(problems)} string(s) break the copy rule: short, plain, no long dashes (CLAUDE.md, «Тексты»).")
        return 1
    print("copy-lint: every interface string is short and has no long dash.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
