"""CLI tests. They run against the emulator only (project demo-wuserade)."""

import os
from datetime import datetime, timezone
from io import BytesIO

import pytest
from firebase_admin import auth
from PIL import Image
from test_photos_emulator import blob_names, jpeg, record_ids, seed_poet, seed_submission

from wuserade_admin import __main__ as cli
from wuserade_admin import store
from wuserade_admin.models import AuthorRow, PoemRow, ThemeRow

pytestmark = pytest.mark.skipif(
    not os.environ.get("FIRESTORE_EMULATOR_HOST"),
    reason="FIRESTORE_EMULATOR_HOST is not set (run through firebase emulators:exec)",
)

NOW = datetime(2024, 3, 1, 12, 0, tzinfo=timezone.utc)


def pg_rows(poem_count: int = 6):
    themes = [ThemeRow(id=1, title="Love"), ThemeRow(id=2, title="Nature")]
    authors = [
        AuthorRow(id=1, name="First", bio="b", photo=""),
        AuthorRow(id=2, name="Second", bio="", photo=None),
    ]
    poems = [
        PoemRow(
            id=n,
            title=f"Poem {n}",
            text="x",
            author_id=(n % 2) + 1,
            theme_id=None if n % 3 == 0 else (n % 2) + 1,
            created_at=NOW,
            updated_at=NOW,
        )
        for n in range(1, poem_count + 1)
    ]
    return themes, authors, poems


@pytest.fixture
def postgres(monkeypatch):
    rows = pg_rows()
    seen = []

    def fake_read_postgres(dsn):
        seen.append(dsn)
        return rows

    monkeypatch.setattr(cli, "read_postgres", fake_read_postgres)
    monkeypatch.delenv("DATABASE_URL", raising=False)
    return seen


def meta(db) -> dict:
    return db.document("meta/content").get().to_dict()


def test_migrate_upserts_rebuilds_and_reports_matching_counts(db, postgres, capsys):
    code = cli.main(["migrate", "--dsn", "postgresql://example/db"])

    out = capsys.readouterr().out
    assert code == 0
    assert postgres == ["postgresql://example/db"]
    assert store.count_documents(db) == {"themes": 2, "authors": 2, "poems": 6}
    assert meta(db)["catalogVersion"] == 1
    assert "themes=2" in out and "poems=6" in out
    assert "match" in out.lower()
    assert "example/db" not in out


def test_migrate_takes_the_dsn_from_the_environment(db, postgres, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://from-env/db")

    assert cli.main(["migrate"]) == 0
    assert postgres == ["postgresql://from-env/db"]


def test_migrate_without_any_dsn_is_a_usage_error(db, postgres, capsys):
    assert cli.main(["migrate"]) == 2
    assert "DATABASE_URL" in capsys.readouterr().err
    assert postgres == []


def test_migrate_exits_non_zero_when_counts_differ(db, postgres, capsys):
    themes, authors, poems = pg_rows()
    only_in_firestore = PoemRow(
        id=900, title="Added later", text="x", author_id=1, theme_id=None, created_at=NOW, updated_at=NOW
    )
    store.upsert_content(db, themes, authors, [*poems, only_in_firestore])

    code = cli.main(["migrate", "--dsn", "postgresql://example/db"])

    captured = capsys.readouterr()
    assert code == 1
    assert "poems" in captured.err
    assert "MISMATCH" in captured.err


def test_rebuild_command_and_min_version_flag(db, capsys):
    store.upsert_content(db, *pg_rows())

    assert cli.main(["rebuild", "--min-version", "1.5"]) == 0
    out = capsys.readouterr().out
    assert "version 1" in out and "6 poems" in out
    assert meta(db)["minimumAppVersion"] == "1.5"

    assert cli.main(["rebuild"]) == 0
    assert meta(db)["minimumAppVersion"] == "1.5"
    assert meta(db)["catalogVersion"] == 2

    assert cli.main(["rebuild", "--min-version", ""]) == 0
    assert meta(db)["minimumAppVersion"] is None


def test_rebuild_with_a_bad_version_reports_an_error(db, capsys):
    store.upsert_content(db, *pg_rows())

    assert cli.main(["rebuild", "--min-version", "latest"]) == 1
    assert "minimum_app_version" in capsys.readouterr().err


def test_add_poem_command_adds_and_rebuilds(db, tmp_path, capsys):
    store.upsert_content(db, *pg_rows())
    store.rebuild(db)
    text_file = tmp_path / "poem.txt"
    text_file.write_text("Ӏуэхугъуэ\nтекст\n", encoding="utf-8")

    code = cli.main(
        ["add-poem", "--title", "Новая", "--text-file", str(text_file), "--author-id", "2", "--theme-id", "1"]
    )

    assert code == 0
    assert "poem 7" in capsys.readouterr().out
    created = db.document("poems/7").get().to_dict()
    assert created["title"] == "Новая"
    assert created["text"] == "Ӏуэхугъуэ\nтекст"
    assert created["authorName"] == "Second"
    assert created["themeId"] == 1
    entries = db.document("catalog/0").get().to_dict()["entries"]
    assert entries[-1]["id"] == 7
    assert meta(db)["catalogVersion"] == 2
    assert meta(db)["nextPoemId"] == 8


def test_add_poem_without_theme_and_with_bad_author(db, tmp_path, capsys):
    store.upsert_content(db, *pg_rows())
    store.rebuild(db)
    text_file = tmp_path / "poem.txt"
    text_file.write_text("text", encoding="utf-8")

    assert cli.main(["add-poem", "--title", "T", "--text-file", str(text_file), "--author-id", "1"]) == 0
    assert db.document("poems/7").get().to_dict()["themeId"] is None

    assert cli.main(["add-poem", "--title", "T", "--text-file", str(text_file), "--author-id", "55"]) == 1
    assert "author 55" in capsys.readouterr().err
    assert not db.document("poems/8").get().exists


def test_add_poem_with_a_missing_text_file(db, tmp_path, capsys):
    store.upsert_content(db, *pg_rows())
    store.rebuild(db)

    code = cli.main(
        ["add-poem", "--title", "T", "--text-file", str(tmp_path / "nope.txt"), "--author-id", "1"]
    )

    assert code == 1
    assert "nope.txt" in capsys.readouterr().err


def test_cli_photos_approve_reject_and_errors(services, capsys):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")

    assert cli.main(["photos", "approve", "7_alice"]) == 0
    out = capsys.readouterr().out
    assert "approved 7_alice" in out
    assert services.db.document("authors/7").get().to_dict()["photoURL"] in out

    assert cli.main(["photos", "reject", "9_nobody"]) == 1
    assert capsys.readouterr().err.startswith("error:")

    assert cli.main(["photos", "approve", "not-an-id"]) == 1
    assert capsys.readouterr().err.startswith("error:")


def test_cli_photos_approve_publishes_the_file_it_is_given(services, tmp_path, capsys):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice", size=(2000, 1000))
    edited = tmp_path / "edited.jpg"
    edited.write_bytes(jpeg((800, 800)))

    assert cli.main(["photos", "approve", "7_alice", "--file", str(edited)]) == 0

    published = services.bucket.blob("poets/7.jpg").download_as_bytes()
    assert Image.open(BytesIO(published)).size == (800, 800)
    assert capsys.readouterr().out.count("approved 7_alice: ") == 1


def test_cli_photos_list_downloads_and_prints_one_line_per_photo(services, tmp_path, capsys):
    seed_poet(services.db, 7)
    seed_poet(services.db, 8)
    seed_submission(services, 8, "bob", created_at=NOW.replace(day=2))
    seed_submission(services, 7, "alice", created_at=NOW)

    assert cli.main(["photos", "list", "--out", str(tmp_path)]) == 0

    lines = capsys.readouterr().out.splitlines()
    assert lines[0].startswith("Using the ")  # which database, as for every other command
    assert lines[1:] == [
        f"7_alice  Author 7  {NOW.astimezone():%Y-%m-%d %H:%M}",
        f"8_bob  Author 8  {NOW.replace(day=2).astimezone():%Y-%m-%d %H:%M}",
        f"2 waiting photos in {tmp_path}",
    ]
    assert sorted(path.name for path in tmp_path.iterdir()) == ["7-Author 7-alice.jpg", "8-Author 8-bob.jpg"]


def test_cli_photos_list_defaults_to_the_downloads_folder(services, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("HOME", str(tmp_path))
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")

    assert cli.main(["photos", "list"]) == 0

    folder = tmp_path / "Downloads" / "wuserade-photos"
    assert capsys.readouterr().out.splitlines()[-1] == f"1 waiting photos in {folder}"
    assert [path.name for path in folder.iterdir()] == ["7-Author 7-alice.jpg"]


def test_cli_photos_list_marks_a_record_without_a_file(services, tmp_path, capsys):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice", created_at=NOW)
    services.bucket.blob("photo-submissions/7/alice.jpg").delete()

    assert cli.main(["photos", "list", "--out", str(tmp_path)]) == 0

    out = capsys.readouterr().out
    assert f"7_alice  Author 7  {NOW.astimezone():%Y-%m-%d %H:%M}  (no photo file)" in out
    assert out.splitlines()[-1] == f"1 waiting photos in {tmp_path}"


def test_cli_photos_reject_and_remove_say_what_they_did(services, capsys):
    seed_poet(services.db, 7)
    seed_submission(services, 7, "alice")
    seed_submission(services, 7, "bob")

    assert cli.main(["photos", "reject", "7_bob"]) == 0
    assert "rejected 7_bob" in capsys.readouterr().out
    assert record_ids(services) == {"7_alice"}

    assert cli.main(["photos", "approve", "7_alice"]) == 0
    capsys.readouterr()
    assert cli.main(["photos", "remove", "7"]) == 0
    assert "removed the photo of poet 7" in capsys.readouterr().out
    assert services.db.document("authors/7").get().to_dict()["photoURL"] is None
    assert blob_names(services) == set()

    assert cli.main(["photos", "remove", "9"]) == 1
    assert capsys.readouterr().err.startswith("error:")


def test_cli_photos_ban_and_unban(services, capsys):
    auth.create_user(uid="alice")
    seed_submission(services, 7, "alice")
    seed_submission(services, 8, "alice")

    assert cli.main(["photos", "ban", "7_alice"]) == 0
    assert "banned alice; deleted 2 waiting photos" in capsys.readouterr().out
    assert auth.get_user("alice").custom_claims == {"photoBan": True}
    assert record_ids(services) == set()

    assert cli.main(["photos", "unban", "alice"]) == 0
    assert "unbanned alice" in capsys.readouterr().out
    assert not auth.get_user("alice").custom_claims


def test_cli_photos_ban_errors(services, capsys):
    assert cli.main(["photos", "ban", "7_a_b"]) == 1
    assert capsys.readouterr().err.startswith("error:")

    assert cli.main(["photos", "ban", "ghost"]) == 1
    assert capsys.readouterr().err.startswith("error:")

    assert cli.main(["photos", "unban", "ghost"]) == 1
    assert capsys.readouterr().err.startswith("error:")


def test_cli_photos_needs_all_three_emulators_or_none(db, monkeypatch, capsys):
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)

    assert cli.main(["photos", "reject", "7_alice"]) == 1
    assert "Auth emulator" in capsys.readouterr().err
