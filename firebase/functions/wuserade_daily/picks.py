"""The rules that pick a day's poem, short poem and poet of the day.

Pure functions over a `Catalog` and the earlier days' picks. Each slot draws from its own
`random.Random(f"{day.isoformat()}:<slot>")`, so re-picking one slot never changes the others, and candidates are sorted by id before a draw, so a date always
gives the same picks for the same inputs, whatever order the catalog is in.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from datetime import date

from .catalog import Catalog, Entry, Poet
from .text import is_unknown_author

MIN_POEM_LINES = 2
MIN_SHORT_LINES = 2
MAX_SHORT_LINES = 9
MIN_POET_POEMS = 3


@dataclass(frozen=True)
class DayPicks:
    poem_id: int
    short_poem_id: int
    poet_id: int


def pick_day(day: date, catalog: Catalog, history: list[DayPicks]) -> DayPicks:
    """The picks for `day`. `history` lists the earlier days, newest first, at most 365 of them.

    1. The day's poem: a random entry of at least 2 lines that was not the poem of a day in
       `history`. When every such entry was, the least recently used one.
    2. The short poem: a random entry of 2 to 9 lines, not the day's poem, that was not the short
       poem of a day in `history`, preferably by a different poet from the day's poem. When every
       short poem was, the least recently used one.
    3. The poet: a random eligible poet (3 or more poems, not the unknown author) who is not in the
       current cycle, preferably not the poet of picks 1 and 2. Cycles are found by replaying
       `history` from its oldest day: a cycle closes once every eligible poet has appeared in it.

    Raises ValueError when the catalog has no poem, no short poem or no poet to pick from.
    """
    poem = _pick_poem(_rng(day, "poem"), catalog, history)
    short_poem = _pick_short_poem(_rng(day, "short"), catalog, history, poem)
    poet = _pick_poet(_rng(day, "poet"), catalog, history, poem, short_poem)
    return DayPicks(poem_id=poem.id, short_poem_id=short_poem.id, poet_id=poet.id)


def top_poems(catalog: Catalog, poet_id: int, n: int = 3) -> list[Entry]:
    """The `n` most viewed poems of the poet, ties going to the newest `created_at` (then the highest id)."""
    poems = [e for e in catalog.entries if e.author_id == poet_id]
    poems.sort(key=lambda e: (e.views, e.created_at, e.id), reverse=True)
    return poems[: max(n, 0)]


def _rng(day: date, slot: str) -> random.Random:
    return random.Random(f"{day.isoformat()}:{slot}")


def _recency(ids_newest_first: list[int]) -> dict[int, int]:
    """Id -> how many days ago it was last used (0 is the newest day in the history)."""
    recency: dict[int, int] = {}
    for days_ago, used_id in enumerate(ids_newest_first):
        recency.setdefault(used_id, days_ago)
    return recency


def _pick_poem(rng: random.Random, catalog: Catalog, history: list[DayPicks]) -> Entry:
    pool = sorted((e for e in catalog.entries if e.lines >= MIN_POEM_LINES), key=lambda e: e.id)
    if not pool:
        raise ValueError(f"the catalog has no poem with at least {MIN_POEM_LINES} lines")
    used = _recency([h.poem_id for h in history])
    unused = [e for e in pool if e.id not in used]
    if unused:
        return rng.choice(unused)
    return max(pool, key=lambda e: used[e.id])


def _pick_short_poem(rng: random.Random, catalog: Catalog, history: list[DayPicks], poem: Entry) -> Entry:
    pool = sorted(
        (e for e in catalog.entries if MIN_SHORT_LINES <= e.lines <= MAX_SHORT_LINES and e.id != poem.id),
        key=lambda e: e.id,
    )
    if not pool:
        raise ValueError(
            f"the catalog has no short poem ({MIN_SHORT_LINES} to {MAX_SHORT_LINES} lines) "
            "other than the day's poem"
        )
    used = _recency([h.short_poem_id for h in history])
    unused = [e for e in pool if e.id not in used]
    if not unused:
        return max(pool, key=lambda e: used[e.id])
    by_another_poet = [e for e in unused if e.author_id != poem.author_id]
    return rng.choice(by_another_poet or unused)


def _eligible_poets(catalog: Catalog) -> list[Poet]:
    return sorted(
        (p for p in catalog.poets if p.poems_count >= MIN_POET_POEMS and not is_unknown_author(p.name)),
        key=lambda p: p.id,
    )


def _poets_in_current_cycle(history: list[DayPicks], eligible_ids: set[int]) -> set[int]:
    """The poets seen in the open cycle, replaying `history` (newest first) from its oldest day.

    A cycle closes, and a new one opens empty, once it covers every eligible poet, so the result
    never covers them all. A history that starts mid-cycle, or poets who became eligible or
    ineligible, only shift where cycles close.
    """
    seen: set[int] = set()
    for picks in reversed(history):
        seen.add(picks.poet_id)
        if eligible_ids <= seen:
            seen = set()
    return seen


def _pick_poet(
    rng: random.Random,
    catalog: Catalog,
    history: list[DayPicks],
    poem: Entry,
    short_poem: Entry,
) -> Poet:
    """The poet of the day: see `pick_day`, rule 3."""
    eligible = _eligible_poets(catalog)
    if not eligible:
        raise ValueError(f"the catalog has no poet with at least {MIN_POET_POEMS} poems")
    in_cycle = _poets_in_current_cycle(history, {p.id for p in eligible})
    candidates = [p for p in eligible if p.id not in in_cycle] or eligible
    avoided = {poem.author_id, short_poem.author_id}
    return rng.choice([p for p in candidates if p.id not in avoided] or candidates)
