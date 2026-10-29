"""Firestore store tests. They run against the emulator only (project demo-wuserade)."""

import os
from collections import Counter
from dataclasses import replace
from datetime import datetime, timedelta, timezone

import pytest
from google.cloud.firestore import DELETE_FIELD
from google.cloud.firestore_v1.batch import WriteBatch
from google.cloud.firestore_v1.document import DocumentReference

from wuserade_admin import store, views
from wuserade_admin.models import AuthorRow, PoemRow, ThemeRow
from wuserade_admin.store import RebuildResult

pytestmark = pytest.mark.skipif(
    not os.environ.get("FIRESTORE_EMULATOR_HOST"),
    reason="FIRESTORE_EMULATOR_HOST is not set (run through firebase emulators:exec)",
)

START = datetime(2024, 3, 1, 12, 0, tzinfo=timezone.utc)


def make_content(poem_count: int):
    """3 themes, 4 authors (author 4 has no poems), `poem_count` poems with ids 1..n."""
    themes = [ThemeRow(id=i, title=f"Theme {i}") for i in (1, 2, 3)]
    authors = [AuthorRow(id=i, name=f"Author {i}", bio=f"Bio {i}", photo=None) for i in (1, 2, 3, 4)]
    theme_ids = [1, 2, 3, None]
    poems = [
        PoemRow(
            id=n,
            title=f"Poem {n}",
            text=f"first line {n}\r\nsecond line {n}",
            author_id=(n % 3) + 1,
            theme_id=theme_ids[n % 4],
            created_at=START + timedelta(minutes=n),
            updated_at=START + timedelta(minutes=n, seconds=30),
            views=n * 3,
        )
        for n in range(1, poem_count + 1)
    ]
    return themes, authors, poems


def doc(db, path: str):
    return db.document(path).get()


def meta(db) -> dict:
    return doc(db, "meta/content").to_dict()


def doc_ids(db, collection: str) -> set[str]:
    return {d.id for d in db.collection(collection).list_documents()}


def test_connect_uses_demo_project_with_the_emulator(db):
    assert db.project == "demo-wuserade"


def test_upsert_then_rebuild_writes_catalog_meta_and_counts(db):
    themes, authors, poems = make_content(2500)

    store.upsert_content(db, themes, authors, poems)
    result = store.rebuild(db)

    assert result == RebuildResult(
        catalog_version=1, chunks=2, poems=2500, authors_with_poems=3, themes=3
    )
    m = meta(db)
    assert m["catalogVersion"] == 1
    assert m["catalogChunks"] == 2
    assert m["nextPoemId"] == 2501
    assert m["minimumAppVersion"] is None
    assert [a["id"] for a in m["authors"]] == [1, 2, 3]
    assert [t["id"] for t in m["themes"]] == [1, 2, 3]

    per_author = Counter(p.author_id for p in poems)
    per_theme = Counter(p.theme_id for p in poems if p.theme_id is not None)
    for a in authors:
        assert doc(db, f"authors/{a.id}").to_dict()["poemsCount"] == per_author[a.id]
    assert doc(db, "authors/4").to_dict()["poemsCount"] == 0
    for t in themes:
        assert doc(db, f"themes/{t.id}").to_dict()["poemsCount"] == per_theme[t.id]
    assert {a["id"]: a["poemsCount"] for a in m["authors"]} == {
        a: per_author[a] for a in (1, 2, 3)
    }

    chunk0 = doc(db, "catalog/0").to_dict()
    chunk1 = doc(db, "catalog/1").to_dict()
    assert chunk0["version"] == 1 and chunk1["version"] == 1
    assert len(chunk0["entries"]) == 2000
    assert len(chunk1["entries"]) == 500
    assert chunk0["entries"][0]["id"] == 1
    assert chunk1["entries"][-1]["id"] == 2500
    assert set(chunk0["entries"][0]) == {
        "id", "title", "authorId", "authorName", "themeId", "lines", "views", "createdAt"
    }
    assert doc_ids(db, "catalog") == {"0", "1"}


def test_upsert_denormalizes_author_name_and_keeps_document_shape(db):
    themes, authors, poems = make_content(5)

    store.upsert_content(db, themes, authors, poems)

    poem = doc(db, "poems/3").to_dict()
    assert poem["id"] == 3
    assert poem["authorId"] == 1
    assert poem["authorName"] == "Author 1"
    assert poem["themeId"] is None
    assert poem["text"] == "first line 3\r\nsecond line 3"
    assert poem["submittedBy"] is None
    assert poem["views"] == 9
    assert poem["createdAt"] == START + timedelta(minutes=3)
    assert poem["updatedAt"] == START + timedelta(minutes=3, seconds=30)
    assert doc(db, "poems/1").to_dict()["themeId"] == 2
    assert doc(db, "authors/1").to_dict().get("photoURL") is None


def test_upsert_keeps_an_approved_photo(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    db.document("authors/1").update({"photoURL": "https://p/1.jpg"})
    store.upsert_content(db, themes, authors, poems)  # Django's photo is blank
    assert doc(db, "authors/1").to_dict()["photoURL"] == "https://p/1.jpg"


def test_rebuild_keeps_photos_in_meta(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    db.document("authors/1").update({"photoURL": "https://p/1.jpg"})
    store.rebuild(db)
    entries = {a["id"]: a for a in meta(db)["authors"]}
    assert entries[1]["photoURL"] == "https://p/1.jpg"
    assert "photoURL" not in entries[2]


def test_rebuild_bumps_version(db):
    themes, authors, poems = make_content(2500)
    store.upsert_content(db, themes, authors, poems)

    store.rebuild(db)
    second = store.rebuild(db)

    assert second.catalog_version == 2
    assert meta(db)["catalogVersion"] == 2
    for chunk_id in ("0", "1"):
        assert doc(db, f"catalog/{chunk_id}").to_dict()["version"] == 2


def test_rebuild_removes_stale_chunks(db):
    themes, authors, poems = make_content(2500)
    store.upsert_content(db, themes, authors, poems)
    assert store.rebuild(db).chunks == 2
    assert doc(db, "catalog/1").exists

    for n in range(1, 1001):
        db.document(f"poems/{n}").delete()
    result = store.rebuild(db)

    assert result.chunks == 1
    assert result.poems == 1500
    assert doc(db, "catalog/0").exists
    assert not doc(db, "catalog/1").exists
    assert meta(db)["catalogChunks"] == 1
    assert doc_ids(db, "catalog") == {"0"}


def test_upsert_is_idempotent(db):
    themes, authors, poems = make_content(30)

    store.upsert_content(db, themes, authors, poems)
    first = store.count_documents(db)
    store.upsert_content(db, themes, authors, poems)

    assert first == {"themes": 3, "authors": 4, "poems": 30}
    assert store.count_documents(db) == first


def test_upsert_splits_writes_into_batches_of_at_most_500(db, monkeypatch):
    sizes = []
    real_batch = db.batch

    def spying_batch():
        batch = real_batch()
        real_set = batch.set
        index = len(sizes)
        sizes.append(0)

        def counting_set(*args, **kwargs):
            sizes[index] += 1
            return real_set(*args, **kwargs)

        batch.set = counting_set
        return batch

    monkeypatch.setattr(db, "batch", spying_batch)
    themes, authors, poems = make_content(1200)

    store.upsert_content(db, themes, authors, poems)

    assert sum(sizes) == 3 + 4 + 1200
    assert max(sizes) <= 500
    assert store.count_documents(db)["poems"] == 1200


def test_load_content_round_trips_what_was_upserted(db):
    themes, authors, poems = make_content(40)
    store.upsert_content(db, themes, authors, poems)

    loaded_themes, loaded_authors, loaded_poems = store.load_content(db)

    assert loaded_themes == themes
    assert loaded_authors == authors
    assert loaded_poems == poems


def test_add_poem_uses_next_id_and_appears_after_rebuild(db):
    themes, authors, poems = make_content(5)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)
    assert meta(db)["nextPoemId"] == 6

    new_id = store.add_poem(db, "New poem", "line 1\nline 2", author_id=2, theme_id=3)

    assert new_id == 6
    created = doc(db, "poems/6").to_dict()
    assert created["id"] == 6
    assert created["title"] == "New poem"
    assert created["text"] == "line 1\nline 2"
    assert created["authorId"] == 2
    assert created["authorName"] == "Author 2"
    assert created["themeId"] == 3
    assert created["submittedBy"] is None
    assert created["views"] == 0
    assert created["createdAt"] == created["updatedAt"]
    assert created["createdAt"].tzinfo is not None
    assert meta(db)["nextPoemId"] == 7

    result = store.rebuild(db)

    assert result.poems == 6
    entries = doc(db, "catalog/0").to_dict()["entries"]
    assert [e["id"] for e in entries] == [1, 2, 3, 4, 5, 6]
    assert entries[-1]["authorName"] == "Author 2"
    assert entries[-1]["themeId"] == 3
    assert meta(db)["nextPoemId"] == 7
    assert doc(db, "themes/3").to_dict()["poemsCount"] == 2


def test_add_poem_twice_without_rebuild_gets_distinct_ids(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)

    first = store.add_poem(db, "A", "a", author_id=1, theme_id=None)
    second = store.add_poem(db, "B", "b", author_id=1, theme_id=None)

    assert (first, second) == (4, 5)
    assert doc(db, "poems/4").to_dict()["title"] == "A"
    assert doc(db, "poems/4").to_dict()["themeId"] is None
    assert doc(db, "poems/5").to_dict()["title"] == "B"
    assert meta(db)["nextPoemId"] == 6


def test_add_poem_rejects_unknown_author_or_theme_and_changes_nothing(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)

    with pytest.raises(ValueError, match="author 99"):
        store.add_poem(db, "T", "x", author_id=99, theme_id=None)
    with pytest.raises(ValueError, match="theme 77"):
        store.add_poem(db, "T", "x", author_id=1, theme_id=77)

    assert meta(db)["nextPoemId"] == 4
    assert not doc(db, "poems/4").exists


def test_add_poem_requires_meta_and_never_overwrites_an_existing_poem(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)

    with pytest.raises(ValueError, match="rebuild"):
        store.add_poem(db, "T", "x", author_id=1, theme_id=None)

    store.rebuild(db)
    db.document("poems/4").set({"id": 4, "title": "added by hand"})
    with pytest.raises(ValueError, match="poems/4"):
        store.add_poem(db, "T", "x", author_id=1, theme_id=None)
    assert doc(db, "poems/4").to_dict()["title"] == "added by hand"


def test_add_poem_rejects_blank_title_or_text(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)

    with pytest.raises(ValueError, match="title"):
        store.add_poem(db, "   ", "x", author_id=1, theme_id=None)
    with pytest.raises(ValueError, match="text"):
        store.add_poem(db, "T", "  \n", author_id=1, theme_id=None)


def test_minimum_app_version_is_kept_unless_given(db):
    themes, authors, poems = make_content(5)
    store.upsert_content(db, themes, authors, poems)

    store.rebuild(db, minimum_app_version="1.5")
    assert meta(db)["minimumAppVersion"] == "1.5"

    store.rebuild(db)
    assert meta(db)["minimumAppVersion"] == "1.5"

    store.rebuild(db, minimum_app_version="1.6.1")
    assert meta(db)["minimumAppVersion"] == "1.6.1"

    store.rebuild(db, minimum_app_version="")
    assert meta(db)["minimumAppVersion"] is None

    store.rebuild(db)
    assert meta(db)["minimumAppVersion"] is None


def test_minimum_app_version_must_look_like_a_version(db):
    themes, authors, poems = make_content(5)
    store.upsert_content(db, themes, authors, poems)

    with pytest.raises(ValueError, match="minimum_app_version"):
        store.rebuild(db, minimum_app_version="v1.5")

    assert not doc(db, "meta/content").exists


def test_rebuild_refreshes_author_name_on_the_authors_poems_only(db):
    themes, authors, poems = make_content(30)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)
    before = {n: doc(db, f"poems/{n}") for n in range(1, 31)}

    # The owner renames author 2 in the Firebase console.
    db.document("authors/2").update({"name": "Renamed Author"})
    store.rebuild(db)

    for n in range(1, 31):
        after = doc(db, f"poems/{n}")
        if poems[n - 1].author_id == 2:
            assert after.to_dict()["authorName"] == "Renamed Author"
            assert {**after.to_dict(), "authorName": None} == {**before[n].to_dict(), "authorName": None}
        else:
            # Not written at all: same document, same update time.
            assert after.to_dict() == before[n].to_dict()
            assert after.update_time == before[n].update_time
    entries = doc(db, "catalog/0").to_dict()["entries"]
    assert {e["authorName"] for e in entries if e["authorId"] == 2} == {"Renamed Author"}
    assert {a["name"] for a in meta(db)["authors"] if a["id"] == 2} == {"Renamed Author"}


def test_rebuild_fills_in_a_missing_author_name_on_a_poem(db):
    themes, authors, poems = make_content(5)
    store.upsert_content(db, themes, authors, poems)
    db.document("poems/3").update({"authorName": DELETE_FIELD})

    store.rebuild(db)

    assert doc(db, "poems/3").to_dict()["authorName"] == "Author 1"


def test_author_name_refresh_is_batched_and_written_before_catalog_and_meta(db, monkeypatch):
    themes, authors, poems = make_content(1800)  # 600 poems per author
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)
    db.document("authors/1").update({"name": "Renamed Author"})

    events = []
    batch_sizes = []
    real_batch = db.batch
    real_update = WriteBatch.update
    real_set = DocumentReference.set

    def spying_batch():
        batch_sizes.append(0)
        return real_batch()

    def spying_update(self, reference, field_updates, *args, **kwargs):
        events.append(("update", reference.path))
        batch_sizes[-1] += 1
        return real_update(self, reference, field_updates, *args, **kwargs)

    def spying_set(self, *args, **kwargs):
        events.append(("set", self.path))
        return real_set(self, *args, **kwargs)

    monkeypatch.setattr(db, "batch", spying_batch)
    monkeypatch.setattr(WriteBatch, "update", spying_update)
    monkeypatch.setattr(DocumentReference, "set", spying_set)

    store.rebuild(db)

    renamed = [path for kind, path in events if kind == "update" and path.startswith("poems/")]
    assert len(renamed) == 600
    assert max(batch_sizes) <= 500
    last_poem_update = max(i for i, (kind, path) in enumerate(events) if path.startswith("poems/"))
    first_chunk_write = min(i for i, (kind, path) in enumerate(events) if path.startswith("catalog/"))
    assert last_poem_update < first_chunk_write
    assert events[-1] == ("set", "meta/content")
    assert all(path != "meta/content" for _, path in events[:-1])


def test_rebuild_never_lowers_next_poem_id(db):
    themes, authors, poems = make_content(10)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)
    assert meta(db)["nextPoemId"] == 11

    db.document("poems/10").delete()
    store.rebuild(db)

    # Reusing id 10 would attach old likes to a different poem.
    assert meta(db)["nextPoemId"] == 11


def test_rebuild_refuses_poem_with_unknown_author_and_writes_nothing(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    db.document("poems/3").update({"authorId": 999})
    before = doc(db, "authors/1").to_dict()

    with pytest.raises(ValueError, match=r"poems/3.*author 999"):
        store.rebuild(db)

    assert not doc(db, "meta/content").exists
    assert doc_ids(db, "catalog") == set()
    assert doc(db, "authors/1").to_dict() == before


def test_oversized_chunk_stops_rebuild_before_any_write(db, monkeypatch):
    themes, authors, poems = make_content(20)
    store.upsert_content(db, themes, authors, poems)
    before = doc(db, "authors/1").to_dict()
    monkeypatch.setattr(store, "MAX_CHUNK_BYTES", 500)

    with pytest.raises(store.ChunkTooLargeError, match="chunk 0"):
        store.rebuild(db)

    assert not doc(db, "meta/content").exists
    assert doc_ids(db, "catalog") == set()
    assert doc(db, "authors/1").to_dict() == before


def test_load_content_names_the_document_with_a_missing_field(db):
    themes, authors, poems = make_content(2)
    store.upsert_content(db, themes, authors, poems)
    db.document("poems/2").update({"title": DELETE_FIELD})

    with pytest.raises(ValueError, match=r"poems/2.*title"):
        store.load_content(db)


def test_count_documents(db):
    assert store.count_documents(db) == {"themes": 0, "authors": 0, "poems": 0}
    themes, authors, poems = make_content(7)
    store.upsert_content(db, themes, authors, poems)

    assert store.count_documents(db) == {"themes": 3, "authors": 4, "poems": 7}


def test_rebuild_puts_lines_and_views_into_the_catalog(db):
    themes, authors, poems = make_content(5)
    poems[1] = replace(poems[1], text="one\r\n\r\ntwo\n\nthree\n", views=1234)
    store.upsert_content(db, themes, authors, poems)

    store.rebuild(db)

    entries = {e["id"]: e for e in doc(db, "catalog/0").to_dict()["entries"]}
    assert entries[2]["lines"] == 3 and entries[2]["views"] == 1234
    assert entries[1]["lines"] == 2 and entries[1]["views"] == 3
    assert entries[5]["views"] == 15


def test_rebuild_recounts_lines_after_a_text_edit_in_the_console(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    store.rebuild(db)

    db.document("poems/2").update({"text": "a\nb\nc\nd"})
    store.rebuild(db)

    entries = {e["id"]: e for e in doc(db, "catalog/0").to_dict()["entries"]}
    assert entries[2]["lines"] == 4


def test_rebuild_counts_a_poem_without_views_as_zero(db):
    themes, authors, poems = make_content(4)
    store.upsert_content(db, themes, authors, poems)
    db.document("poems/2").update({"views": DELETE_FIELD})
    db.document("poems/3").update({"views": None})

    store.rebuild(db)

    entries = {e["id"]: e for e in doc(db, "catalog/0").to_dict()["entries"]}
    assert [entries[n]["views"] for n in (1, 2, 3, 4)] == [3, 0, 0, 12]


def test_copy_views_skips_unknown_poems_and_rebuild_reads_them(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)

    written = views.copy_views(db, {1: 10, 2: 0, 99: 5})
    store.rebuild(db)

    assert written == 2
    assert not doc(db, "poems/99").exists
    assert doc(db, "poems/1").to_dict()["views"] == 10
    assert doc(db, "poems/2").to_dict()["views"] == 0
    entries = {e["id"]: e for e in doc(db, "catalog/0").to_dict()["entries"]}
    assert entries[1]["views"] == 10
    assert entries[2]["views"] == 0
    assert entries[3]["views"] == 9  # not in the dump: keeps what it had


def test_copy_views_changes_only_the_views_field(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    before = {n: doc(db, f"poems/{n}") for n in (1, 2, 3)}

    views.copy_views(db, {1: 500})

    assert doc(db, "poems/1").to_dict() == {**before[1].to_dict(), "views": 500}
    for n in (2, 3):
        assert doc(db, f"poems/{n}").to_dict() == before[n].to_dict()
        assert doc(db, f"poems/{n}").update_time == before[n].update_time
    assert not doc(db, "meta/content").exists  # only the command rebuilds the catalog


def test_copy_views_with_nothing_to_copy_writes_nothing(db):
    themes, authors, poems = make_content(2)
    store.upsert_content(db, themes, authors, poems)
    before = doc(db, "poems/1")

    assert views.copy_views(db, {}) == 0
    assert views.copy_views(db, {50: 1, 51: 2}) == 0
    assert doc(db, "poems/1").update_time == before.update_time


def test_copy_views_can_be_run_again_with_a_newer_dump(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)

    assert views.copy_views(db, {1: 10, 2: 20}) == 2
    assert views.copy_views(db, {1: 11, 2: 20}) == 2

    assert [doc(db, f"poems/{n}").to_dict()["views"] for n in (1, 2, 3)] == [11, 20, 9]


def test_copy_views_splits_writes_into_batches_of_at_most_500(db, monkeypatch):
    themes, authors, poems = make_content(1200)
    store.upsert_content(db, themes, authors, poems)
    sizes = []
    real_batch = db.batch

    def spying_batch():
        batch = real_batch()
        real_update = batch.update
        index = len(sizes)
        sizes.append(0)

        def counting_update(*args, **kwargs):
            sizes[index] += 1
            return real_update(*args, **kwargs)

        batch.update = counting_update
        return batch

    monkeypatch.setattr(db, "batch", spying_batch)

    written = views.copy_views(db, {n: n + 1000 for n in range(1, 1201)} | {5000: 1})

    assert written == 1200
    assert sum(sizes) == 1200
    assert max(sizes) <= 500
    assert doc(db, "poems/1200").to_dict()["views"] == 2200
