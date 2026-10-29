"""The daily documents against the emulator (project demo-wuserade)."""

from datetime import date, datetime, timezone

from wuserade_daily.catalog import load_catalog
from wuserade_daily.daily import read_history, resync_days, write_missing_days
from wuserade_daily.picks import DayPicks

CREATED = datetime(2024, 3, 1, 12, 0, tzinfo=timezone.utc)
TODAY = date(2026, 10, 29)

# Poets 1 to 3 have 4 poems each (ids 1-4, 5-8, 9-12), all of 4 lines.
POET_OF = {n: (n - 1) // 4 + 1 for n in range(1, 13)}


def seed(db, drop_poems=(), drop_poets=()):
    """Write meta/content, catalog/0 and poems/{id} for 12 poems by 3 poets, minus the dropped ones."""
    entries = [
        {
            "id": n,
            "title": f"Poem {n}",
            "authorId": POET_OF[n],
            "authorName": f"Poet {POET_OF[n]}",
            "themeId": None,
            "createdAt": CREATED,
            "lines": 4,
            "views": n,
        }
        for n in range(1, 13)
        if n not in drop_poems and POET_OF[n] not in drop_poets
    ]
    authors = [
        {"id": p, "name": f"Poet {p}", "poemsCount": 4, **({"photoURL": f"https://x/{p}.jpg"} if p == 1 else {})}
        for p in (1, 2, 3)
        if p not in drop_poets
    ]
    db.document("meta/content").set({"catalogVersion": 1, "catalogChunks": 1, "authors": authors, "themes": []})
    db.document("catalog/0").set({"version": 1, "entries": entries})
    for e in entries:
        db.document(f"poems/{e['id']}").set({"id": e["id"], "text": f"line a {e['id']}\nline b\nline c\nline d"})


def daily(db, day: str) -> dict:
    return db.document(f"daily/{day}").get().to_dict()


def test_write_missing_days_covers_every_time_zone(db):
    seed(db)

    written = write_missing_days(db, TODAY)

    ids = {d.id for d in db.collection("daily").list_documents()}
    assert ids == {f"2026-10-{d}" for d in range(28, 32)} | {f"2026-11-0{d}" for d in range(1, 6)}
    assert written == sorted(ids)


def test_write_missing_days_never_rewrites_a_written_day(db):
    seed(db)
    write_missing_days(db, TODAY)
    db.document("daily/2026-10-29").update({"poem.id": 999})

    written = write_missing_days(db, TODAY)

    assert written == []
    assert daily(db, "2026-10-29")["poem"]["id"] == 999


def test_write_missing_days_fills_only_the_gaps_and_sees_the_days_written_before(db):
    seed(db)
    write_missing_days(db, TODAY)
    db.document("daily/2026-11-04").delete()
    db.document("daily/2026-11-05").delete()

    written = write_missing_days(db, date(2026, 10, 30))

    assert written == ["2026-11-04", "2026-11-05", "2026-11-06"]
    # 12 poems, 10 days: while unused poems remain, no poem repeats, so each day saw the ones before.
    poem_ids = [daily(db, d.id)["poem"]["id"] for d in db.collection("daily").list_documents()]
    assert len(poem_ids) == len(set(poem_ids)) == 10


def test_read_history_is_the_earlier_days_newest_first_within_the_window(db):
    for day, n in (("2026-10-27", 1), ("2026-10-28", 2), ("2026-10-29", 3), ("2026-10-31", 4), ("2025-10-01", 5)):
        db.document(f"daily/{day}").set({"poem": {"id": n}, "shortPoem": {"id": n + 10}, "poet": {"id": 1}})

    assert read_history(db, before=date(2026, 10, 29)) == [DayPicks(2, 12, 1), DayPicks(1, 11, 1)]
    assert read_history(db, before=date(2026, 10, 29), days=1) == [DayPicks(2, 12, 1)]


def test_document_shape_matches_spec(db):
    seed(db)
    write_missing_days(db, TODAY)

    doc = daily(db, "2026-10-29")
    assert set(doc) == {"date", "poem", "shortPoem", "poet", "createdAt"}
    assert doc["date"] == "2026-10-29"
    assert doc["createdAt"] is not None
    for slot in ("poem", "shortPoem"):
        assert set(doc[slot]) == {"id", "title", "authorId", "authorName", "text"}
        assert doc[slot]["text"] == f"line a {doc[slot]['id']}\nline b\nline c\nline d"
        assert doc[slot]["title"] == f"Poem {doc[slot]['id']}"
    poet = doc["poet"]
    assert set(poet) - {"photoURL"} == {"id", "name", "poemsCount", "topPoems"}
    assert ("photoURL" in poet) == (poet["id"] == 1)
    assert poet["poemsCount"] == 4
    assert len(poet["topPoems"]) == 3
    assert all(set(t) == {"id", "title"} for t in poet["topPoems"])


def test_resync_refreshes_corrected_text_from_yesterday_on_only(db):
    seed(db)
    write_missing_days(db, TODAY)
    # A day before yesterday, which resync must leave alone.
    old = {**daily(db, "2026-10-28"), "date": "2026-10-27"}
    db.document("daily/2026-10-27").set(old)
    for n in range(1, 13):
        db.document(f"poems/{n}").update({"text": "corrected"})

    changed = resync_days(db, TODAY, load_catalog(db))

    assert "2026-10-27" not in changed
    assert daily(db, "2026-10-27")["poem"]["text"] == old["poem"]["text"] != "corrected"
    for day in ("2026-10-28", "2026-10-29", "2026-11-05"):
        assert daily(db, day)["poem"]["text"] == "corrected"
        assert daily(db, day)["shortPoem"]["text"] == "corrected"
    assert changed == sorted(changed) == [f"2026-10-{d}" for d in range(28, 32)] + [f"2026-11-0{d}" for d in range(1, 6)]


def test_resync_writes_nothing_when_nothing_changed(db):
    seed(db)
    write_missing_days(db, TODAY)
    before = daily(db, "2026-10-29")

    assert resync_days(db, TODAY, load_catalog(db)) == []

    assert daily(db, "2026-10-29") == before


def test_resync_repicks_a_removed_poem_and_a_removed_poet(db):
    seed(db)
    write_missing_days(db, TODAY)
    before = daily(db, "2026-10-30")
    gone_poem = before["poem"]["id"]
    gone_poet = before["poet"]["id"]
    seed(db, drop_poems=(gone_poem,), drop_poets=(gone_poet,))

    changed = resync_days(db, TODAY, load_catalog(db))

    assert "2026-10-30" in changed
    after = daily(db, "2026-10-30")
    assert after["poem"]["id"] != gone_poem
    assert after["poem"]["authorId"] != gone_poet
    assert after["poet"]["id"] != gone_poet
    assert after["shortPoem"]["id"] != after["poem"]["id"]
    assert after["createdAt"] == before["createdAt"]


def test_resync_repicks_only_the_poet_when_only_the_poet_is_gone(db):
    seed(db)
    write_missing_days(db, TODAY)
    before = daily(db, "2026-10-30")
    meta = db.document("meta/content").get().to_dict()
    meta["authors"] = [a for a in meta["authors"] if a["id"] != before["poet"]["id"]]
    db.document("meta/content").set(meta)

    resync_days(db, TODAY, load_catalog(db))

    after = daily(db, "2026-10-30")
    assert after["poet"]["id"] != before["poet"]["id"]
    assert after["poem"]["id"] == before["poem"]["id"]
    assert after["shortPoem"]["id"] == before["shortPoem"]["id"]
