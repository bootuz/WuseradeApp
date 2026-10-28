"""CLI tests. They run against the emulator only (project demo-wuserade)."""

import os
from datetime import datetime, timezone

import pytest

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
