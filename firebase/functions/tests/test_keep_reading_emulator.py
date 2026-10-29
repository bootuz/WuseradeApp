"""keep_reading against the emulator (project demo-wuserade)."""

from datetime import datetime, timezone

from wuserade_daily.catalog import load_catalog
from wuserade_daily.keep_reading import keep_reading

CREATED = datetime(2024, 3, 1, tzinfo=timezone.utc)
NOW = datetime(2026, 10, 29, tzinfo=timezone.utc)


def write_catalog(db, spec, themed=True):
    entries = [
        {"id": n, "title": f"Poem {n}", "authorId": a, "authorName": f"Poet {a}",
         "themeId": 7 if themed and a in (1, 2) else None, "createdAt": CREATED, "lines": 10, "views": n}
        for n, a in spec
    ]
    db.document("meta/content").set({"catalogVersion": 1, "catalogChunks": 1, "authors": [], "themes": []})
    db.document("catalog/0").set({"version": 1, "entries": entries})


def seed(db, themed=True):
    """Poet 1 has poems 1-8, poet 2 has 11-14 (theme 7), poet 3 has 21-22; all 10 lines."""
    write_catalog(db, [(n, 1) for n in range(1, 9)] + [(n, 2) for n in range(11, 15)] + [(21, 3), (22, 3)], themed)


def read(db, uid, *ids):
    for i in ids:
        db.document(f"users/{uid}/reads/{i}").set({"poemId": i, "readAt": NOW})


def test_keep_reading_filters_by_the_callers_reads_only(db):
    seed(db)
    read(db, "u1", 8, 7)
    catalog = load_catalog(db)

    mine = keep_reading(db, "u1", 1, catalog)
    theirs = keep_reading(db, "u2", 1, catalog)

    assert [p["id"] for p in mine["poet"]] == [6, 5, 4]
    assert [p["id"] for p in theirs["poet"]] == [8, 7, 6]
    assert mine["poet"][0] == {"id": 6, "title": "Poem 6"}


def test_keep_reading_similar_has_title_and_poet_and_skips_read(db):
    seed(db)
    read(db, "u1", 14)

    result = keep_reading(db, "u1", 1, load_catalog(db))

    assert result["similar"] == [
        {"id": 13, "title": "Poem 13", "authorId": 2, "authorName": "Poet 2"},
        {"id": 12, "title": "Poem 12", "authorId": 2, "authorName": "Poet 2"},
    ]


def test_keep_reading_uses_the_callers_liked_poets_when_the_theme_is_thin(db):
    seed(db, themed=False)
    db.document("users/u1/likes/11").set({"poemId": 11, "likedAt": NOW, "authorId": 2})

    liked = keep_reading(db, "u1", 1, load_catalog(db))
    other = keep_reading(db, "u2", 1, load_catalog(db))

    assert [p["id"] for p in liked["similar"]] == [14, 13]  # the liked poet's poems, most read first
    assert [p["id"] for p in other["similar"]] == [22, 21]  # nothing liked: poems of similar length


def test_keep_reading_reads_at_most_25_read_documents(db, monkeypatch):
    write_catalog(db, [(n, 1) for n in range(1, 40)] + [(100 + n, 2) for n in range(40)])
    catalog = load_catalog(db)
    counts = []
    real = db.get_all

    def counting(refs, *args, **kwargs):
        refs = list(refs)
        counts.append(len(refs))
        return real(refs, *args, **kwargs)

    monkeypatch.setattr(db, "get_all", counting)

    result = keep_reading(db, "u1", 1, catalog)

    assert len(counts) == 1 and counts[0] <= 25
    assert len(result["poet"]) == 3 and len(result["similar"]) == 2
