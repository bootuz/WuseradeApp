from datetime import datetime, timezone

import pytest

from wuserade_daily.catalog import Catalog, Entry, Poet, load_catalog

CREATED = datetime(2024, 3, 1, 12, 30, tzinfo=timezone.utc)


class FakeSnapshot:
    def __init__(self, data):
        self._data = data

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return self._data


class FakeDb:
    """Just `db.document(path).get()`, over a dict of path -> document."""

    def __init__(self, documents):
        self.documents = documents

    def document(self, path):
        snapshot = FakeSnapshot(self.documents.get(path))
        return type("Ref", (), {"get": lambda self: snapshot})()


def raw_entry(poem_id, **overrides):
    entry = {
        "id": poem_id,
        "title": f"Poem {poem_id}",
        "authorId": 7,
        "authorName": "Poet 7",
        "themeId": 3,
        "createdAt": CREATED,
        "lines": 12,
        "views": 40,
    }
    entry.update(overrides)
    return entry


def meta(version=5, chunks=2, authors=None):
    return {
        "catalogVersion": version,
        "catalogChunks": chunks,
        "authors": authors if authors is not None else [{"id": 7, "name": "Poet 7", "poemsCount": 9}],
        "themes": [],
    }


def test_load_catalog_joins_the_chunks_in_order_and_reads_every_field():
    db = FakeDb(
        {
            "meta/content": meta(),
            "catalog/0": {"version": 5, "entries": [raw_entry(1), raw_entry(2, themeId=None, title="")]},
            "catalog/1": {"version": 5, "entries": [raw_entry(3, lines=2, views=0)]},
        }
    )

    catalog = load_catalog(db)

    assert catalog == Catalog(
        version=5,
        entries=[
            Entry(1, "Poem 1", 7, "Poet 7", 3, 12, 40, CREATED),
            Entry(2, "", 7, "Poet 7", None, 12, 40, CREATED),
            Entry(3, "Poem 3", 7, "Poet 7", 3, 2, 0, CREATED),
        ],
        poets=[Poet(7, "Poet 7", 9, None)],
    )


def test_missing_lines_or_views_read_as_zero():
    old_entry = raw_entry(1)
    del old_entry["lines"]
    del old_entry["views"]
    half_old = raw_entry(2)
    del half_old["views"]
    chunk = {"version": 5, "entries": [old_entry, half_old]}
    db = FakeDb({"meta/content": meta(chunks=1), "catalog/0": chunk})

    entries = load_catalog(db).entries

    assert [(e.lines, e.views) for e in entries] == [(0, 0), (12, 0)]


def test_poets_carry_their_photo_url_when_they_have_one():
    authors = [
        {"id": 1, "name": "A", "poemsCount": 3, "photoURL": "https://example.com/1.jpg"},
        {"id": 2, "name": "B", "poemsCount": 4},
    ]
    db = FakeDb({"meta/content": meta(chunks=1, authors=authors), "catalog/0": {"version": 5, "entries": []}})

    assert load_catalog(db).poets == [
        Poet(1, "A", 3, "https://example.com/1.jpg"),
        Poet(2, "B", 4, None),
    ]


def test_an_entry_without_a_creation_time_sorts_as_the_oldest():
    entry = raw_entry(1)
    del entry["createdAt"]
    db = FakeDb({"meta/content": meta(chunks=1), "catalog/0": {"version": 5, "entries": [entry]}})

    created = load_catalog(db).entries[0].created_at

    assert created < CREATED


def test_load_catalog_without_meta_says_to_run_rebuild():
    with pytest.raises(ValueError, match="rebuild"):
        load_catalog(FakeDb({}))


def test_load_catalog_refuses_a_missing_chunk():
    db = FakeDb({"meta/content": meta(), "catalog/0": {"version": 5, "entries": []}})

    with pytest.raises(ValueError, match="catalog/1"):
        load_catalog(db)


def test_load_catalog_refuses_a_chunk_from_another_version():
    # A rebuild is half way: the app refuses this too.
    db = FakeDb(
        {
            "meta/content": meta(chunks=2),
            "catalog/0": {"version": 5, "entries": []},
            "catalog/1": {"version": 4, "entries": []},
        }
    )

    with pytest.raises(ValueError, match="version"):
        load_catalog(db)


def test_load_catalog_from_the_emulator(db):
    authors = [{"id": 7, "name": "Poet 7", "poemsCount": 9, "photoURL": "u"}]
    db.document("meta/content").set(meta(chunks=2, authors=authors))
    db.document("catalog/0").set({"version": 5, "entries": [raw_entry(1), raw_entry(2, themeId=None)]})
    db.document("catalog/1").set({"version": 5, "entries": [raw_entry(3)]})

    catalog = load_catalog(db)

    assert catalog.version == 5
    assert [e.id for e in catalog.entries] == [1, 2, 3]
    assert catalog.entries[1].theme_id is None
    assert catalog.entries[0].created_at == CREATED
    assert catalog.poets == [Poet(7, "Poet 7", 9, "u")]
