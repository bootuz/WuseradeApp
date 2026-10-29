"""Photo approval tests. They run against the Firestore, Storage and Auth emulators (project demo-wuserade)."""

import time
from datetime import datetime, timezone
from io import BytesIO
from types import SimpleNamespace
from urllib.parse import parse_qs, urlsplit
from urllib.request import urlopen

import firebase_admin
import pytest
from firebase_admin import auth
from google.api_core.exceptions import FailedPrecondition
from google.cloud.firestore_v1.document import DocumentReference
from PIL import Image

from wuserade_admin import photos


def jpeg(size: tuple[int, int]) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", size, (30, 90, 160)).save(buffer, "JPEG")
    return buffer.getvalue()


def seed_poet(db, author_id: int) -> None:
    """`authors/{id}` without a photo, and an entry for the poet in `meta/content` (version 3)."""
    db.document(f"authors/{author_id}").set(
        {"id": author_id, "name": f"Author {author_id}", "bio": "", "photoURL": None, "poemsCount": 2}
    )
    meta_ref = db.document("meta/content")
    meta = meta_ref.get().to_dict() or {"catalogVersion": 3, "catalogChunks": 1}
    meta["authors"] = [*meta.get("authors", []), {"id": author_id, "name": f"Author {author_id}", "poemsCount": 2}]
    meta_ref.set(meta)


def seed_file(services, author_id: int, uid: str, size: tuple[int, int] = (100, 100)) -> None:
    """A waiting photo in Storage and nothing else, like an upload whose record was never written."""
    services.bucket.blob(photos.submission_path(author_id, uid)).upload_from_string(
        jpeg(size), content_type="image/jpeg"
    )


def seed_submission(
    services,
    author_id: int,
    uid: str,
    size: tuple[int, int] = (100, 100),
    created_at: datetime | None = None,
) -> None:
    """A waiting photo: the file in Storage and its record (made now, unless `created_at` says when)."""
    seed_file(services, author_id, uid, size)
    services.db.document(f"photoSubmissions/{author_id}_{uid}").set(
        {"authorId": author_id, "submittedBy": uid, "createdAt": created_at or datetime.now(timezone.utc)}
    )


def record_ids(services) -> set[str]:
    return {ref.id for ref in services.db.collection("photoSubmissions").list_documents()}


def blob_names(services) -> set[str]:
    return {blob.name for blob in services.bucket.list_blobs()}


def meta(services) -> dict:
    return services.db.document("meta/content").get().to_dict()


def author(services, author_id: int) -> dict:
    return services.db.document(f"authors/{author_id}").get().to_dict()


def test_connect_uses_the_emulators(services):
    assert services.db.project == "demo-wuserade"
    assert services.bucket.name == photos.EMULATOR_BUCKET
    assert services.download_host == photos.storage_emulator_host()
    assert firebase_admin.get_app().project_id == "demo-wuserade"


def test_approve_publishes_and_updates_both_places(services):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice", size=(2000, 1000))

    url = photos.approve(services, "7_alice")

    blob = services.bucket.get_blob("poets/7.jpg")
    assert blob is not None
    assert blob.content_type == "image/jpeg"
    assert blob.cache_control == "public, max-age=31536000"
    data = blob.download_as_bytes()
    assert max(Image.open(BytesIO(data)).size) <= 1024
    assert author(services, 7)["photoURL"] == url
    after = meta(services)
    assert after["authors"][0]["photoURL"] == url
    assert after["catalogVersion"] == 3
    assert url.startswith(services.download_host)
    # A public get on poets/ works without it, so check the token itself: the stored one is in the URL.
    assert parse_qs(urlsplit(url).query)["token"] == [blob.metadata["firebaseStorageDownloadTokens"]]
    with urlopen(url) as response:
        assert response.read() == data


def test_approve_clears_every_waiting_submission_for_that_poet(services):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    seed_submission(services, 7, "bob")
    seed_submission(services, 8, "carol")

    photos.approve(services, "7_alice")

    assert record_ids(services) == {"8_carol"}
    assert blob_names(services) == {"poets/7.jpg", "photo-submissions/8/carol.jpg"}


def test_approve_with_file_publishes_the_owners_copy(services, tmp_path):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice", size=(2000, 1000))
    edited = tmp_path / "edited.jpg"
    edited.write_bytes(jpeg((800, 800)))

    photos.approve(services, "7_alice", file=edited)

    published = services.bucket.blob("poets/7.jpg").download_as_bytes()
    assert Image.open(BytesIO(published)).size == (800, 800)


def test_approve_again_changes_the_url(services):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    url1 = photos.approve(services, "7_alice")
    seed_submission(services, 7, "bob")

    url2 = photos.approve(services, "7_bob")

    assert url2 != url1
    assert author(services, 7)["photoURL"] == url2
    assert meta(services)["authors"][0]["photoURL"] == url2


def test_approve_for_a_poet_missing_from_meta_raises_and_changes_nothing(services):
    seed_poet(services.db, 7)
    services.db.document("meta/content").update({"authors": []})
    seed_submission(services, 7, "alice")

    with pytest.raises(ValueError, match="meta/content"):
        photos.approve(services, "7_alice")

    assert blob_names(services) == {"photo-submissions/7/alice.jpg"}
    assert record_ids(services) == {"7_alice"}
    assert author(services, 7)["photoURL"] is None


def test_approve_for_a_poet_without_an_author_document_raises_and_changes_nothing(services):
    seed_poet(services.db, 7)
    services.db.document("authors/7").delete()
    seed_submission(services, 7, "alice")

    with pytest.raises(ValueError, match="authors/7"):
        photos.approve(services, "7_alice")

    assert blob_names(services) == {"photo-submissions/7/alice.jpg"}
    assert record_ids(services) == {"7_alice"}


def test_approve_unknown_submission_raises(services):
    seed_poet(services.db, 7)
    seed_file(services, 7, "alice")

    with pytest.raises(ValueError, match="7_alice"):
        photos.approve(services, "7_alice")

    assert blob_names(services) == {"photo-submissions/7/alice.jpg"}


@pytest.mark.parametrize(
    ("stored", "message"),
    [(None, "7_alice has no photo file"), (b"definitely not an image", "not an image")],
    ids=["missing file", "not an image"],
)
def test_approve_with_a_bad_submission_file_raises_and_changes_nothing(services, stored, message):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    blob = services.bucket.blob(photos.submission_path(7, "alice"))
    if stored is None:
        blob.delete()
    else:
        blob.upload_from_string(stored, content_type="image/jpeg")

    with pytest.raises(ValueError, match=message):
        photos.approve(services, "7_alice")

    assert not any(name.startswith("poets/") for name in blob_names(services))
    assert record_ids(services) == {"7_alice"}
    assert author(services, 7)["photoURL"] is None
    assert "photoURL" not in meta(services)["authors"][0]


def test_approve_with_an_unreadable_file_raises_and_changes_nothing(services, tmp_path):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")

    with pytest.raises(ValueError, match="missing.jpg"):
        photos.approve(services, "7_alice", file=tmp_path / "missing.jpg")

    assert not any(name.startswith("poets/") for name in blob_names(services))
    assert record_ids(services) == {"7_alice"}


def test_reject_deletes_the_record_and_file(services):
    seed_submission(services, 7, "alice")
    seed_submission(services, 7, "bob")

    photos.reject(services, "7_alice")

    assert record_ids(services) == {"7_bob"}
    assert blob_names(services) == {"photo-submissions/7/bob.jpg"}


def test_reject_unknown_submission_raises(services):
    with pytest.raises(ValueError, match="7_alice"):
        photos.reject(services, "7_alice")


def test_reject_removes_a_file_whose_record_was_never_written(services):
    seed_file(services, 7, "alice")

    photos.reject(services, "7_alice")

    assert blob_names(services) == set()


def test_reject_removes_a_record_whose_file_is_gone(services):
    seed_submission(services, 7, "alice")
    services.bucket.blob(photos.submission_path(7, "alice")).delete()

    photos.reject(services, "7_alice")

    assert record_ids(services) == set()


@pytest.fixture
def precondition_failure(monkeypatch):
    """Deleting a document fails the way production may answer `exists=True` for a missing record."""

    def delete(self, *args, **kwargs):
        raise FailedPrecondition("the document does not exist")

    monkeypatch.setattr(DocumentReference, "delete", delete)


def test_reject_treats_a_failed_precondition_as_no_record(services, precondition_failure):
    seed_file(services, 7, "alice")

    photos.reject(services, "7_alice")

    assert blob_names(services) == set()


def test_reject_with_a_failed_precondition_and_no_file_raises(services, precondition_failure):
    with pytest.raises(ValueError, match="7_alice"):
        photos.reject(services, "7_alice")


def test_remove_clears_the_photo_everywhere(services):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    photos.approve(services, "7_alice")

    photos.remove(services, 7)

    assert author(services, 7)["photoURL"] is None
    after = meta(services)
    assert after["authors"] == [{"id": 7, "name": "Author 7", "poemsCount": 2}]
    assert after["catalogVersion"] == 3
    assert blob_names(services) == set()


def test_remove_takes_down_a_photo_of_a_poet_no_longer_in_meta(services):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    photos.approve(services, "7_alice")
    services.db.document("meta/content").update({"authors": []})

    photos.remove(services, 7)

    assert author(services, 7)["photoURL"] is None
    assert blob_names(services) == set()


def test_remove_without_a_photo_is_harmless(services):
    seed_poet(services.db, 7)

    photos.remove(services, 7)

    assert author(services, 7)["photoURL"] is None


def test_remove_unknown_poet_raises(services):
    with pytest.raises(ValueError, match="authors/9"):
        photos.remove(services, 9)


def test_delete_submissions_by_author_also_removes_files_without_a_record(services):
    seed_submission(services, 7, "alice")
    seed_file(services, 7, "dave")
    seed_submission(services, 8, "carol")

    assert photos.delete_submissions(services, author_id=7) == 2

    assert record_ids(services) == {"8_carol"}
    assert blob_names(services) == {"photo-submissions/8/carol.jpg"}


def test_delete_submissions_by_uid_also_removes_files_without_a_record(services):
    seed_file(services, 8, "alice")
    seed_submission(services, 7, "alice")
    seed_submission(services, 7, "bob")

    assert photos.delete_submissions(services, uid="alice") == 2

    assert record_ids(services) == {"7_bob"}
    assert blob_names(services) == {"photo-submissions/7/bob.jpg"}


def test_delete_submissions_by_uid_does_not_touch_a_uid_that_only_ends_the_same(services):
    seed_submission(services, 7, "malice")
    seed_submission(services, 7, "alice")

    assert photos.delete_submissions(services, uid="alice") == 1

    assert record_ids(services) == {"7_malice"}
    assert blob_names(services) == {"photo-submissions/7/malice.jpg"}


def test_delete_submissions_skips_a_file_that_vanished_after_it_was_listed(services, monkeypatch):
    seed_submission(services, 7, "alice")
    ghost = services.bucket.blob(photos.submission_path(7, "ghost"))  # listed, but there is no such file
    listing = services.bucket.list_blobs
    monkeypatch.setattr(services.bucket, "list_blobs", lambda **options: [ghost, *listing(**options)])

    assert photos.delete_submissions(services, author_id=7) == 1

    assert record_ids(services) == set()
    assert {blob.name for blob in listing()} == set()  # the real listing: `list_blobs` is patched


def test_delete_submissions_with_nothing_waiting_returns_zero(services):
    assert photos.delete_submissions(services, author_id=7) == 0
    assert photos.delete_submissions(services, uid="alice") == 0


@pytest.mark.parametrize("filters", [{}, {"author_id": 7, "uid": "alice"}])
def test_delete_submissions_needs_exactly_one_filter(services, filters):
    with pytest.raises(ValueError, match="author_id or uid"):
        photos.delete_submissions(services, **filters)


MARCH_1 = datetime(2024, 3, 1, 12, 0, tzinfo=timezone.utc)
MARCH_2 = datetime(2024, 3, 2, 9, 30, tzinfo=timezone.utc)


def test_list_downloads_each_waiting_photo(services, tmp_path):
    seed_poet(services.db, 7)
    seed_poet(services.db, 8)
    seed_submission(services, 8, "bob", size=(120, 80), created_at=MARCH_2)
    seed_submission(services, 7, "alice", size=(100, 100), created_at=MARCH_1)

    listed = photos.list_submissions(services, tmp_path)

    assert listed == [
        photos.Submission("7_alice", 7, "alice", "Author 7", MARCH_1, tmp_path / "7-Author 7-alice.jpg"),
        photos.Submission("8_bob", 8, "bob", "Author 8", MARCH_2, tmp_path / "8-Author 8-bob.jpg"),
    ]
    assert listed[0].path.read_bytes() == jpeg((100, 100))
    assert listed[1].path.read_bytes() == jpeg((120, 80))
    assert record_ids(services) == {"7_alice", "8_bob"}  # listing deletes nothing
    assert blob_names(services) == {"photo-submissions/7/alice.jpg", "photo-submissions/8/bob.jpg"}


def test_list_names_the_file_after_the_poet_and_the_first_six_characters_of_the_uid(services, tmp_path):
    seed_poet(services.db, 7)
    services.db.document("authors/7").update({"name": "A/B\\C:D"})
    seed_submission(services, 7, "abcdefghij")
    folder = tmp_path / "not" / "there" / "yet"

    listed = photos.list_submissions(services, folder)

    assert [s.path for s in listed] == [folder / "7-A-B-C-D-abcdef.jpg"]
    assert listed[0].path.exists()
    assert listed[0].poet_name == "A/B\\C:D"


def test_list_includes_a_file_without_a_record(services, tmp_path):
    seed_poet(services.db, 7)
    seed_submission(services, 8, "bob", created_at=MARCH_1)
    seed_submission(services, 9, "dave", created_at=datetime(2099, 1, 1, tzinfo=timezone.utc))
    seed_file(services, 7, "carol", size=(90, 90))

    listed = photos.list_submissions(services, tmp_path)

    assert [s.id for s in listed] == ["8_bob", "7_carol", "9_dave"]  # oldest first, by the file's age for carol
    carol = listed[1]
    assert (carol.author_id, carol.uid, carol.poet_name) == (7, "carol", "Author 7")
    assert carol.created_at == services.bucket.get_blob("photo-submissions/7/carol.jpg").time_created
    assert carol.path == tmp_path / "7-Author 7-carol.jpg"
    assert carol.path.read_bytes() == jpeg((90, 90))


def test_list_shows_a_record_whose_file_is_gone(services, tmp_path):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    services.bucket.blob(photos.submission_path(7, "alice")).delete()

    listed = photos.list_submissions(services, tmp_path)

    assert [(s.id, s.path) for s in listed] == [("7_alice", None)]
    assert list(tmp_path.iterdir()) == []


def land_after_the_first_read(services, monkeypatch, author_id: int, uid: str) -> None:
    """A submission lands right after the first of `list_submissions`' two reads, records and files.

    Whichever read comes first, the sender's app has uploaded the file and written the record by
    the time the second read starts, just as it does in real life.
    """
    landed = []

    def land() -> None:
        if not landed:
            landed.append(uid)
            seed_submission(services, author_id, uid)

    list_blobs = services.bucket.list_blobs
    collection = services.db.collection

    def list_blobs_then_land(**options):
        blobs = list(list_blobs(**options))
        land()
        return blobs

    def collection_that_lands_after_streaming(name):
        reference = collection(name)
        if name != photos.SUBMISSIONS:
            return reference

        def stream():
            yield from list(reference.stream())
            land()

        return SimpleNamespace(stream=stream)

    monkeypatch.setattr(services.bucket, "list_blobs", list_blobs_then_land)
    monkeypatch.setattr(services.db, "collection", collection_that_lands_after_streaming)


def test_list_shows_a_submission_that_lands_between_the_two_reads_with_its_photo(services, tmp_path, monkeypatch):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice", created_at=MARCH_1)
    land_after_the_first_read(services, monkeypatch, 7, "late")

    listed = photos.list_submissions(services, tmp_path)

    # Never "7_late with a record but no file": the records are read before the files.
    assert [s.id for s in listed] == ["7_alice", "7_late"]
    assert all(s.path is not None and s.path.exists() for s in listed)


def test_list_shows_a_record_whose_file_vanished_after_the_files_were_listed(services, tmp_path, monkeypatch):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice", created_at=MARCH_1)
    seed_submission(services, 7, "bob", created_at=MARCH_2)
    list_blobs = services.bucket.list_blobs

    def list_blobs_then_delete_alices_file(**options):
        blobs = list(list_blobs(**options))
        services.bucket.blob(photos.submission_path(7, "alice")).delete()
        return blobs

    monkeypatch.setattr(services.bucket, "list_blobs", list_blobs_then_delete_alices_file)

    listed = photos.list_submissions(services, tmp_path)

    assert [(s.id, s.path) for s in listed] == [("7_alice", None), ("7_bob", tmp_path / "7-Author 7-bob.jpg")]
    assert [path.name for path in tmp_path.iterdir()] == ["7-Author 7-bob.jpg"]  # no empty file left behind


def test_list_names_a_poet_without_an_author_document(services, tmp_path):
    seed_submission(services, 9, "alice")

    listed = photos.list_submissions(services, tmp_path)

    assert [(s.id, s.poet_name) for s in listed] == [("9_alice", "(unknown poet)")]
    assert listed[0].path.exists()


def test_list_with_nothing_waiting_returns_nothing(services, tmp_path):
    seed_poet(services.db, 7)
    services.bucket.blob("poets/7.jpg").upload_from_string(jpeg((50, 50)), content_type="image/jpeg")

    assert photos.list_submissions(services, tmp_path) == []
    assert list(tmp_path.iterdir()) == []


def test_ban_sets_the_claim_revokes_tokens_and_deletes_waiting_photos(services):
    auth.create_user(uid="alice")
    before = auth.get_user("alice").tokens_valid_after_timestamp
    seed_submission(services, 7, "alice")
    seed_submission(services, 8, "alice")
    seed_submission(services, 7, "bob")
    time.sleep(1.1)  # tokens_valid_after_timestamp counts whole seconds

    assert photos.ban(services, "alice") == 2

    user = auth.get_user("alice")
    assert user.custom_claims == {"photoBan": True}
    assert user.tokens_valid_after_timestamp > before
    assert record_ids(services) == {"7_bob"}
    assert blob_names(services) == {"photo-submissions/7/bob.jpg"}


def test_ban_takes_a_submission_id_and_keeps_other_claims(services):
    auth.create_user(uid="alice")
    auth.set_custom_user_claims("alice", {"x": 1})
    seed_submission(services, 7, "alice")
    seed_submission(services, 7, "bob")

    assert photos.ban(services, "7_alice") == 1

    assert auth.get_user("alice").custom_claims == {"x": 1, "photoBan": True}
    assert record_ids(services) == {"7_bob"}


def test_ban_an_account_without_waiting_photos_deletes_nothing(services):
    auth.create_user(uid="alice")

    assert photos.ban(services, "alice") == 0

    assert auth.get_user("alice").custom_claims == {"photoBan": True}


def test_ban_an_unknown_account_raises_and_deletes_nothing(services):
    seed_submission(services, 7, "ghost")

    with pytest.raises(ValueError, match="ghost"):
        photos.ban(services, "ghost")

    assert record_ids(services) == {"7_ghost"}
    assert blob_names(services) == {"photo-submissions/7/ghost.jpg"}


@pytest.mark.parametrize("target", ["7_alice_2", "_alice", "x_alice"])
def test_ban_with_a_malformed_submission_id_raises(services, target):
    auth.create_user(uid="alice")

    with pytest.raises(ValueError, match="submission id"):
        photos.ban(services, target)

    assert not auth.get_user("alice").custom_claims


@pytest.mark.parametrize(
    ("claims", "left"),
    [({"x": 1, "photoBan": True}, {"x": 1}), ({"photoBan": True}, {})],
    ids=["other claims stay", "no other claims"],
)
def test_unban_removes_only_the_claim(services, claims, left):
    auth.create_user(uid="alice")
    auth.set_custom_user_claims("alice", claims)

    photos.unban(services, "alice")

    assert (auth.get_user("alice").custom_claims or {}) == left


def test_unban_an_unknown_account_raises(services):
    with pytest.raises(ValueError, match="ghost"):
        photos.unban(services, "ghost")
