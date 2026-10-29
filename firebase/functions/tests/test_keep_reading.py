"""The keep-reading ranking and choice (pure)."""

from datetime import datetime, timezone

from wuserade_daily.catalog import Catalog, Entry
from wuserade_daily.keep_reading import Candidates, CatalogCache, choose, rank

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


def test_catalog_cache_reloads_only_when_the_version_changes():
    db, cache = _FakeDb(), CatalogCache()
    first = cache.get(db)
    db.reads.clear()

    assert cache.get(db) is first
    assert db.reads == ["meta/content"]

    db.version = 2
    assert cache.get(db).version == 2
