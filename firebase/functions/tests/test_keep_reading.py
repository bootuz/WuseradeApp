"""The keep-reading ranking and choice (pure)."""

import random
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

import wuserade_daily.keep_reading as kr
from wuserade_daily.catalog import Catalog, Entry
from wuserade_daily.keep_reading import Candidates, CatalogCache, choose, keep_reading, rank

CREATED = datetime(2024, 3, 1, tzinfo=timezone.utc)


def entry(id, author=1, theme=None, lines=10, views=0):
    return Entry(id, f"P{id}", author, f"Poet {author}", theme, lines, views, CREATED)


def catalog(*entries):
    return Catalog(version=1, entries=list(entries), poets=[])


def test_poet_list_is_most_read_first_and_skips_read():
    cat = catalog(entry(10, views=0), entry(11, views=50), entry(12, views=40), entry(13, views=30),
                  entry(14, views=20), entry(15, views=10), entry(99, author=2, views=999))

    c = rank(10, cat, set())

    assert c.poet == [11, 12, 13, 14, 15]
    assert choose(c, set())[0] == [11, 12, 13]
    assert choose(c, {11})[0] == [12, 13, 14]


def test_ranking_caps_each_list():
    mine = [entry(i, views=i) for i in range(1, 20)]
    others = [entry(100 + i, author=2, theme=7, views=i) for i in range(20)]
    more = [entry(200 + i, author=3, views=i) for i in range(20)]
    cat = catalog(entry(50, theme=7), *mine, *others, *more)

    c = rank(50, cat, {2, 3})

    assert len(c.poet) == 10 and c.poet[0] == 19
    assert len(c.theme) == 5 and c.theme[0] == 119
    assert len(c.liked) == 5 and len(c.length) == 5


def test_similar_fills_from_theme_then_liked_then_length():
    cat = catalog(
        entry(1, author=1, theme=7, lines=10),
        entry(2, author=2, theme=7, lines=30, views=5),    # theme
        entry(3, author=3, theme=8, lines=30, views=9),    # liked poet
        entry(4, author=4, theme=8, lines=11, views=1),    # similar length
        entry(5, author=5, theme=8, lines=12, views=100),  # similar length, more read
    )

    c = rank(1, cat, {3})

    assert c.theme == [2] and c.liked == [3] and c.length == [5, 4]
    assert choose(c, set())[1] == [2, 3]
    assert choose(c, {2})[1] == [3, 5]
    assert choose(c, {2, 3})[1] == [5, 4]


def test_no_id_in_two_lists_and_never_the_poem_itself():
    cat = catalog(
        entry(1, author=1, theme=7, views=1),
        entry(2, author=1, theme=7, views=2),
        entry(3, author=2, theme=7, views=3),
        entry(4, author=3, theme=7, views=4),
        entry(5, author=3, theme=9, views=5),
    )

    c = rank(1, cat, {3, 2})

    ids = c.poet + c.theme + c.liked + c.length
    assert len(ids) == len(set(ids))
    assert 1 not in ids
    assert c.poet == [2]
    assert c.theme == [4, 3]
    assert c.liked == [5]
    assert c.length == []


def test_length_window_is_three_lines_either_way():
    cat = catalog(entry(1, lines=10), entry(2, author=2, lines=13), entry(3, author=3, lines=14),
                  entry(4, author=4, lines=7), entry(5, author=5, lines=6))

    assert sorted(rank(1, cat, set()).length) == [2, 4]


def test_poem_without_theme_uses_liked_then_length():
    cat = catalog(
        entry(1, author=1, theme=None, lines=10),
        entry(2, author=2, theme=None, lines=10, views=9),  # a missing theme matches nothing
        entry(3, author=3, theme=4, lines=40, views=1),     # liked poet
    )

    c = rank(1, cat, {3})

    assert c.theme == []
    assert c.liked == [3]
    assert c.length == [2]
    assert choose(c, set())[1] == [3, 2]


def test_choose_returns_at_most_three_and_two():
    c = Candidates(poet=[1, 2, 3, 4], theme=[5, 6, 7], liked=[8], length=[9])

    assert choose(c, set()) == ([1, 2, 3], [5, 6])


class _Snap:
    exists = True

    def __init__(self, data):
        self._data = data

    def to_dict(self):
        return self._data


class _FakeDb:
    def __init__(self):
        self.version, self.reads = 1, []

    def document(self, path):
        db = self
        db.reads.append(path)

        class Ref:
            def get(self):
                if path == "meta/content":
                    return _Snap({"catalogVersion": db.version, "catalogChunks": 1, "authors": []})
                return _Snap({"version": db.version, "entries": [{"id": 1, "authorId": 1}]})

        return Ref()


class _Clock:
    """Seconds, moved by hand."""

    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def test_catalog_cache_reloads_only_when_the_version_changes():
    clock = _Clock()
    db, cache = _FakeDb(), CatalogCache(clock=clock)
    first = cache.get(db)
    db.reads.clear()

    clock.now += 60
    assert cache.get(db) is first
    assert db.reads == ["meta/content"]

    db.version = 2
    clock.now += 60
    assert cache.get(db).version == 2


def test_catalog_cache_checks_the_version_at_most_once_a_minute():
    clock = _Clock()
    db, cache = _FakeDb(), CatalogCache(clock=clock)
    first = cache.get(db)
    db.reads.clear()

    db.version = 2
    clock.now += 59
    assert cache.get(db) is first  # within the minute: no read at all, the old version is served
    assert cache.get(db) is first
    assert db.reads == []

    clock.now += 1
    assert cache.get(db).version == 2
    assert db.reads[0] == "meta/content"

    db.reads.clear()
    clock.now += 30
    cache.get(db)
    assert db.reads == []  # the minute counts from the last check


def test_get_all_order_does_not_matter():
    class Snap:
        def __init__(self, id, exists):
            self.id, self.exists = id, exists

    class Db:
        def document(self, path):
            return path

        def get_all(self, refs):
            # Reversed; only poem 3 has been read.
            return [Snap(r.rsplit("/", 1)[1], r.endswith("/3")) for r in reversed(list(refs))]

    cat = catalog(entry(1, theme=7), entry(2, views=3), entry(3, views=2), entry(4, views=1),
                  *[entry(10 + i, author=3 + i, theme=7) for i in range(5)])

    result = keep_reading(Db(), "u", 1, cat)

    assert [p["id"] for p in result["poet"]] == [2, 4]


def test_cache_loads_once_per_version_and_survives_a_failing_reload(monkeypatch, caplog):
    loads = []
    state = {"version": 1, "fail": False}

    def fake_load(db):
        loads.append(state["version"])
        if state["fail"]:
            raise ValueError("a rebuild is probably running")
        return Catalog(version=state["version"], entries=[], poets=[])

    monkeypatch.setattr(kr, "load_catalog", fake_load)
    clock = _Clock()
    db, cache = _FakeDb(), CatalogCache(clock=clock)

    state["fail"] = True
    with pytest.raises(ValueError):  # nothing cached: the error is raised
        cache.get(db)

    state["fail"] = False
    first = cache.get(db)
    clock.now += 60
    cache.get(db)
    assert len(loads) == 2  # the failed try and one load; the second get was cached

    db.version, state["version"], state["fail"] = 2, 2, True
    clock.now += 60
    assert cache.get(db) is first  # the reload fails: the previous catalog is served
    assert "catalog reload failed" in caplog.text
    assert len(loads) == 3

    state["fail"] = False
    assert cache.get(db).version == 2  # the next call tries again
    assert len(loads) == 4
    cache.get(db)
    assert len(loads) == 4


# Checking the reads in two rounds: first only the poems that would be shown, then the rest of a list only
# when one of its shown poems turns out to be read.


class _ReadsDb:
    """`read` holds the caller's read poem ids; every get_all call's poem ids are recorded, in order."""

    def __init__(self, read=()):
        self.read, self.calls = set(read), []

    def document(self, path):
        return path

    def get_all(self, refs):
        ids = [int(r.rsplit("/", 1)[1]) for r in refs]
        self.calls.append(ids)
        return [SimpleNamespace(id=str(i), exists=i in self.read) for i in reversed(ids)]

    def collection(self, path):  # the likes, read only when the theme is thin: none here
        return SimpleNamespace(order_by=lambda *a, **k: SimpleNamespace(limit=lambda n: SimpleNamespace(stream=lambda: [])))

    @property
    def fetched(self):
        return sum(len(c) for c in self.calls)


# Poem 1 is read now. Poet 1 has 11 other poems (ids 2-12); poets 3-12 write 10 poems in theme 7 (ids 20-29),
# and poets 13-22 write 10 of a similar length outside it (ids 40-49). Most read first means the lowest id first.
_CAT = catalog(
    entry(1, theme=7, lines=10),
    *[entry(i, theme=7, lines=10, views=100 - i) for i in range(2, 13)],
    *[entry(i, author=i - 17, theme=7, lines=30, views=100 - i) for i in range(20, 30)],
    *[entry(i, author=i - 27, theme=8, lines=11, views=100 - i) for i in range(40, 50)],
)
_THIN = catalog(  # theme 7 has one other poem: the similar list fills from length
    entry(1, theme=7, lines=10),
    *[entry(i, lines=10, views=100 - i) for i in range(2, 13)],
    entry(20, author=3, theme=7, lines=30),
    *[entry(i, author=i - 27, theme=8, lines=11, views=100 - i) for i in range(40, 50)],
)


def _full(cat, read):
    """What one check of every candidate returns: the behaviour the two rounds must keep."""
    poet, similar = choose(rank(1, cat, set()), set(read))
    return [p for p in poet], [s for s in similar]


def _ids(result):
    return [p["id"] for p in result["poet"]], [s["id"] for s in result["similar"]]


def _all_candidates(cat):
    c = rank(1, cat, set())
    return [*c.poet, *c.theme, *c.liked, *c.length]


@pytest.mark.parametrize("cat", [_CAT, _THIN], ids=["themed", "thin"])
def test_two_rounds_return_what_one_full_check_returns(cat):
    candidates = _all_candidates(cat)
    rng = random.Random(7)
    cases = [set(), set(candidates)] + [
        {i for i in candidates if rng.random() < p} for p in (0.1, 0.3, 0.5, 0.8) for _ in range(50)
    ]
    for read in cases:
        assert _ids(keep_reading(_ReadsDb(read), "u", 1, cat)) == _full(cat, read), sorted(read)


def test_nothing_read_fetches_only_the_five_shown():
    db = _ReadsDb()

    result = keep_reading(db, "u", 1, _CAT)

    assert db.calls == [[2, 3, 4, 20, 21]]  # display order: 3 by the poet, then 2 similar
    assert _ids(result) == ([2, 3, 4], [20, 21])


def test_a_read_poet_poem_fetches_only_the_rest_of_the_poet():
    db = _ReadsDb({3})

    result = keep_reading(db, "u", 1, _CAT)

    assert db.calls == [[2, 3, 4, 20, 21], [5, 6, 7, 8, 9, 10, 11]]
    assert _ids(result) == ([2, 4, 5], [20, 21])


def test_a_read_similar_poem_fetches_only_the_rest_of_the_similar():
    db = _ReadsDb({20})

    result = keep_reading(db, "u", 1, _CAT)

    assert db.calls[0] == [2, 3, 4, 20, 21]
    assert db.calls[1] == [22, 23, 24, 40, 41, 42, 43, 44]
    assert db.fetched == 13
    assert _ids(result) == ([2, 3, 4], [21, 22])


def test_everything_read_fetches_each_candidate_once():
    candidates = _all_candidates(_CAT)
    db = _ReadsDb(candidates)

    result = keep_reading(db, "u", 1, _CAT)

    assert len(db.calls) == 2 and db.fetched == len(candidates) == 20
    assert sorted(i for call in db.calls for i in call) == sorted(candidates)
    assert _ids(result) == ([], [])
