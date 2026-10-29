"""Kabardian text helpers.

The palochka is always Ӏ (U+04C0), as in the app's `KabardianText` (wuserade/Text/KabardianText.swift):
the server text mixes U+04CF, U+0406 and the Latin letters I, l and 1 for it, and Alegreya draws
U+04CF almost exactly like a Latin l.
"""

from __future__ import annotations

import re

PALOCHKA = "\u04c0"

# The placeholder author of poems with no known poet, spelled as in the app's Author.swift.
UNKNOWN_AUTHOR = "Зытхар тщ\u04c0экъым"

# Always the palochka: U+04CF (small palochka) and U+0406 (Ukrainian І).
_PALOCHKA_VARIANTS = "\u04cf\u0406"
# Only the palochka when a Cyrillic letter is next to them.
_LATIN_LOOKALIKES = "Il1"

# The only line separators: other Unicode separators stay inside their line. The admin tool counts
# `lines` the same way.
_LINE_BREAK = re.compile(r"\r\n|\n|\r")


def _is_cyrillic_letter(character: str | None) -> bool:
    return character is not None and "Ѐ" <= character <= "ӿ" and character.isalpha()


def normalize(s: str) -> str:
    """`s` trimmed, with every palochka spelling turned into Ӏ (U+04C0).

    U+04CF and U+0406 always become Ӏ. Latin I, l and 1 do when a Cyrillic letter is next to them,
    so 'тщIэ' is fixed while 'Illinois' and '1990' are left alone.
    """
    out = []
    for index, character in enumerate(s):
        if character in _PALOCHKA_VARIANTS:
            out.append(PALOCHKA)
        elif character in _LATIN_LOOKALIKES:
            before = s[index - 1] if index > 0 else None
            after = s[index + 1] if index + 1 < len(s) else None
            out.append(PALOCHKA if _is_cyrillic_letter(before) or _is_cyrillic_letter(after) else character)
        else:
            out.append(character)
    return "".join(out).strip()


_UNKNOWN_AUTHOR_KEY = normalize(UNKNOWN_AUTHOR).casefold()


def is_unknown_author(name: str) -> bool:
    """True for the placeholder author, whatever the case or the palochka spelling."""
    return normalize(name).casefold() == _UNKNOWN_AUTHOR_KEY


def sentence_case(title: str) -> str:
    """Sentence case, so a small-caps title such as 'ПСЫ ЦӀЫКӀУ' reads 'Псы цӀыкӀу'.

    Lower-casing turns Ӏ into U+04CF, so the palochka is restored to U+04C0 afterwards.
    """
    lowered = normalize(title).lower().replace("\u04cf", PALOCHKA)
    return lowered[:1].upper() + lowered[1:]


def first_lines(text: str, n: int) -> list[str]:
    """The first `n` non-blank lines of `text`, each stripped."""
    lines: list[str] = []
    for raw in _LINE_BREAK.split(text):
        if len(lines) >= n:
            break
        line = raw.strip()
        if line:
            lines.append(line)
    return lines
