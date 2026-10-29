from datetime import date, datetime, timedelta, timezone

import pytest

from wuserade_daily.catalog import Catalog, Entry, Poet
from wuserade_daily.picks import DayPicks, pick_day, top_poems

D = date(2026, 10, 29)
CREATED = datetime(2024, 1, 1, tzinfo=timezone.utc)
UNKNOWN = "Зытхар тщIэкъым"  # Latin I for the palochka: still the placeholder author

# Line counts of one poet's ten poems: a one-liner, six short poems (2 to 9 lines), three long ones.
LINE_PATTERN = [1, 2, 5, 9, 10, 14, 4, 6, 12, 3]


def entry(
    poem_id: int,
    *,
    author: int = 1,
    lines: int = 4,
    title: str | None = None,
    views: int = 0,
    created: datetime = CREATED,
) -> Entry:
    return Entry(
        id=poem_id,
        title=f"Poem {poem_id}" if title is None else title,
        author_id=author,
        author_name=f"Poet {author}",
        theme_id=None,
        lines=lines,
        views=views,
        created_at=created,
    )


def poet(poet_id: int, *, poems: int = 10, name: str | None = None) -> Poet:
    return Poet(id=poet_id, name=name or f"Poet {poet_id}", poems_count=poems, photo_url=None)


def standard_catalog(poet_ids=range(1, 7)) -> Catalog:
    """Every poet has the ten poems of LINE_PATTERN, with ids poet*100 + position."""
    entries = [
        entry(poet_id * 100 + position, author=poet_id, lines=lines)
        for poet_id in poet_ids
        for position, lines in enumerate(LINE_PATTERN)
    ]
    return Catalog(version=1, entries=entries, poets=[poet(poet_id) for poet_id in poet_ids])


CAT = standard_catalog()


def small_catalog(entries: list[Entry], poets: list[Poet]) -> Catalog:
    return Catalog(version=1, entries=entries, poets=poets)


def by_id(catalog: Catalog) -> dict[int, Entry]:
    return {e.id: e for e in catalog.entries}


def run_days(catalog: Catalog, days: int, start: date = D) -> list[DayPicks]:
    """Pick `days` consecutive days, feeding each day's picks into the next day's history."""
    history: list[DayPicks] = []
    picks: list[DayPicks] = []
    for offset in range(days):
        today = pick_day(start + timedelta(days=offset), catalog, history)
        picks.append(today)
        history = [today, *history][:365]
    return picks


def dates(count: int):
    return [D + timedelta(days=offset) for offset in range(count)]


# ---------------------------------------------------------------- determinism


def test_pick_day_is_deterministic():
    assert pick_day(D, CAT, []) == pick_day(D, CAT, [])


def test_pick_day_varies_with_the_date():
    assert len({pick_day(day, CAT, []).poem_id for day in dates(30)}) > 1


def test_pick_day_does_not_depend_on_the_order_of_the_catalog():
    shuffled = Catalog(version=1, entries=list(reversed(CAT.entries)), poets=list(reversed(CAT.poets)))

    for day in dates(10):
        assert pick_day(day, shuffled, []) == pick_day(day, CAT, [])


# ---------------------------------------------------------------- the day's poem


def test_day_poem_has_two_lines_and_is_not_repeated_within_history():
    entries = by_id(CAT)

    picks = run_days(CAT, 40)

    assert all(entries[p.poem_id].lines >= 2 for p in picks)
    assert len({p.poem_id for p in picks}) == 40


def test_one_line_poems_are_never_the_day_poem():
    catalog = small_catalog(
        [entry(1, lines=1), entry(2, lines=1), entry(3, lines=2), entry(4, lines=30), entry(5, lines=3)],
        [poet(1)],
    )

    assert {pick_day(day, catalog, []).poem_id for day in dates(40)} <= {3, 4, 5}


def test_day_poem_is_spread_over_the_whole_catalog():
    catalog = small_catalog([entry(i, lines=4) for i in range(1, 101)], [poet(1, poems=100)])

    picked = {pick_day(day, catalog, []).poem_id for day in dates(60)}

    assert max(picked) > 80 and min(picked) < 20


def test_day_poem_falls_back_to_the_least_recently_used_when_every_poem_is_used():
    catalog = small_catalog([entry(1, lines=4), entry(2, lines=5), entry(3, lines=6)], [poet(1)])
    # Newest first: 2 was the poem yesterday, 3 the day before, 1 the day before that.
    history = [DayPicks(2, 1, 1), DayPicks(3, 1, 1), DayPicks(1, 1, 1)]

    assert pick_day(D, catalog, history).poem_id == 1


def test_a_poem_that_was_only_a_short_poem_is_still_free_to_be_the_day_poem():
    catalog = Catalog(
        version=1,
        entries=[entry(1, lines=4), entry(2, lines=12), entry(3, lines=4)],
        poets=[poet(1, poems=3)],
    )
    # Poems 2 and 3 have been the day's poem. Poem 1 has only been the short poem, so it is free.
    history = [DayPicks(2, 1, 1), DayPicks(3, 1, 1)]

    assert pick_day(D, catalog, history).poem_id == 1


def test_untitled_poems_can_be_picked():
    catalog = Catalog(
        version=1,
        entries=[entry(i, lines=4, title="") for i in range(1, 6)],
        poets=[poet(1, poems=5)],
    )

    today = pick_day(D, catalog, [])

    assert today.poem_id in range(1, 6)
    assert today.short_poem_id in range(1, 6)


# ---------------------------------------------------------------- the short poem


def test_short_poem_is_2_to_9_lines_and_not_the_day_poem():
    entries = by_id(CAT)

    picks = run_days(CAT, 40)

    assert all(2 <= entries[p.short_poem_id].lines <= 9 for p in picks)
    assert all(p.short_poem_id != p.poem_id for p in picks)


def test_short_poem_is_not_repeated_until_every_short_poem_has_been_used():
    picks = run_days(CAT, 30)  # 36 short poems in the catalog

    assert len({p.short_poem_id for p in picks}) == 30


def test_short_poems_fall_back_to_the_least_recently_used_when_exhausted():
    catalog = Catalog(
        version=1,
        entries=[entry(11, lines=4), entry(12, lines=4), entry(13, lines=4), entry(21, lines=12)],
        poets=[poet(1, poems=4)],
    )
    # Every poem has been the day's poem, but 21; every short poem has been used, 11 longest ago.
    history = [DayPicks(11, 12, 1), DayPicks(12, 13, 1), DayPicks(13, 11, 1)]

    today = pick_day(D, catalog, history)

    assert today.poem_id == 21
    assert today.short_poem_id == 11


def test_exhausted_short_poems_still_never_repeat_the_day_poem():
    catalog = Catalog(
        version=1,
        entries=[entry(11, lines=4), entry(12, lines=4), entry(21, lines=12)],
        poets=[poet(1, poems=3)],
    )
    # The day's poem is the only one not used as a poem yet: 11. Both short poems have been used,
    # 11 the least recently, but 11 is the day's poem.
    history = [DayPicks(12, 12, 1), DayPicks(21, 11, 1)]

    today = pick_day(D, catalog, history)

    assert today.poem_id == 11
    assert today.short_poem_id == 12


def test_short_poem_prefers_a_different_poet_from_the_day_poem():
    entries = by_id(CAT)

    for day in dates(40):
        today = pick_day(day, CAT, [])
        assert entries[today.short_poem_id].author_id != entries[today.poem_id].author_id


def test_short_poem_may_share_the_poet_when_there_is_no_other():
    catalog = standard_catalog(poet_ids=[1])
    entries = by_id(catalog)

    today = pick_day(D, catalog, [])

    assert entries[today.short_poem_id].author_id == entries[today.poem_id].author_id == 1


# ---------------------------------------------------------------- the poet of the day


def test_every_eligible_poet_appears_once_before_any_repeats():
    picks = run_days(CAT, 20)
    poets = [p.poet_id for p in picks]

    for start in (0, 6, 12):
        assert len(set(poets[start : start + 6])) == 6
    assert set(poets) == {1, 2, 3, 4, 5, 6}


def test_poet_is_the_only_one_missing_from_the_current_cycle():
    # Newest first. The newest five days cover poets 2 to 6; the sixth day (poet 1) would complete
    # the cycle, so a new one begins only after the five. Older days no longer matter.
    history = [DayPicks(101, 102, poet_id) for poet_id in (2, 3, 4, 5, 6, 1, 2, 3)]

    assert {pick_day(day, CAT, history).poet_id for day in dates(20)} == {1}


def test_poet_is_never_one_of_the_current_cycle():
    history = [DayPicks(101, 102, 1), DayPicks(103, 104, 2)]

    assert {pick_day(day, CAT, history).poet_id for day in dates(40)} <= {3, 4, 5, 6}


def test_a_cycle_with_a_repeated_poet_still_ends_when_the_run_covers_everyone():
    # Poets 1 to 3 are eligible. Newest first: 1, 2, 1 and then 3 would complete coverage, so the
    # run is the first three days (poets 1 and 2) and only 3 is left.
    catalog = standard_catalog(poet_ids=[1, 2, 3])
    history = [DayPicks(101, 102, poet_id) for poet_id in (1, 2, 1, 3)]

    assert {pick_day(day, catalog, history).poet_id for day in dates(20)} == {3}


def test_unknown_author_and_poets_under_three_poems_are_never_poet_of_the_day():
    catalog = Catalog(
        version=1,
        entries=standard_catalog(poet_ids=[1, 2, 3, 4]).entries,
        poets=[
            poet(1, poems=10),
            poet(2, poems=10, name=UNKNOWN),
            poet(3, poems=2),
            poet(4, poems=3),
        ],
    )

    poets = {p.poet_id for p in run_days(catalog, 30)}

    assert poets == {1, 4}


def test_poems_of_the_unknown_author_can_still_be_the_day_poem_and_the_short_poem():
    catalog = Catalog(
        version=1,
        entries=standard_catalog(poet_ids=[1, 2]).entries,
        poets=[poet(1, poems=10), poet(2, poems=10, name=UNKNOWN)],
    )
    authors = {e.id: e.author_id for e in catalog.entries}

    picks = run_days(catalog, 20)

    assert any(authors[p.poem_id] == 2 for p in picks)
    assert any(authors[p.short_poem_id] == 2 for p in picks)
    assert all(p.poet_id == 1 for p in picks)


def test_three_different_poets_when_possible():
    entries = by_id(CAT)

    for day in dates(60):
        today = pick_day(day, CAT, [])
        authors = {entries[today.poem_id].author_id, entries[today.short_poem_id].author_id, today.poet_id}
        assert len(authors) == 3


def test_the_poet_of_the_day_may_be_the_poet_of_a_poem_when_no_one_else_is_left():
    # Only poet 1 has poems to pick; poets 2 and 3 have only one-liners but are eligible poets.
    entries = [entry(i, author=1, lines=4) for i in range(1, 6)]
    entries += [entry(100 + i, author=2, lines=1) for i in range(3)]
    entries += [entry(200 + i, author=3, lines=1) for i in range(3)]
    catalog = small_catalog(entries, [poet(1, poems=5), poet(2, poems=3), poet(3, poems=3)])
    history = [DayPicks(1, 2, 3), DayPicks(2, 3, 2)]  # poets 3 and 2 are in the cycle

    today = pick_day(D, catalog, history)

    assert today.poet_id == 1


# ---------------------------------------------------------------- a catalog that cannot be picked from


def test_pick_day_says_why_when_nothing_can_be_picked():
    no_long_poem = small_catalog([entry(1, lines=1)], [poet(1)])
    no_short_poem = small_catalog([entry(1, lines=12)], [poet(1)])
    no_eligible_poet = small_catalog([entry(1, lines=4), entry(2, lines=4)], [poet(1, poems=2)])

    with pytest.raises(ValueError, match="at least 2 lines"):
        pick_day(D, no_long_poem, [])
    with pytest.raises(ValueError, match="short poem"):
        pick_day(D, no_short_poem, [])
    with pytest.raises(ValueError, match="poet"):
        pick_day(D, no_eligible_poet, [])


# ---------------------------------------------------------------- top poems


def test_top_poems_highest_views_then_newest():
    later = CREATED + timedelta(days=1)
    latest = CREATED + timedelta(days=2)
    catalog = Catalog(
        version=1,
        entries=[
            entry(1, author=7, views=5),
            entry(2, author=7, views=9, created=CREATED),
            entry(3, author=7, views=9, created=latest),
            entry(4, author=7, views=1),
            entry(5, author=7, views=9, created=later),
            entry(6, author=8, views=99),
        ],
        poets=[poet(7), poet(8)],
    )

    assert [e.id for e in top_poems(catalog, 7)] == [3, 5, 2]
    assert [e.id for e in top_poems(catalog, 7, n=4)] == [3, 5, 2, 1]
    assert [e.id for e in top_poems(catalog, 7, n=1)] == [3]


def test_top_poems_of_a_poet_with_fewer_poems_than_asked_or_none():
    catalog = small_catalog([entry(1, author=7, views=2), entry(2, author=7, views=3)], [poet(7)])

    assert [e.id for e in top_poems(catalog, 7)] == [2, 1]
    assert top_poems(catalog, 99) == []
    assert top_poems(catalog, 7, n=0) == []


def test_top_poems_keeps_one_liners_and_untitled_poems():
    catalog = Catalog(
        version=1,
        entries=[entry(1, author=7, lines=1, views=10), entry(2, author=7, title="", views=5)],
        poets=[poet(7)],
    )

    assert [e.id for e in top_poems(catalog, 7)] == [1, 2]
