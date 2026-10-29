import json
from datetime import datetime, timezone

from wuserade_admin.catalog import (
    CHUNK_SIZE,
    author_document,
    catalog_entries,
    chunk,
    line_count,
    meta_document,
    poem_document,
    theme_document,
)
from wuserade_admin.models import AuthorRow, PoemRow, ThemeRow

CREATED = datetime(2024, 3, 1, 12, 30, tzinfo=timezone.utc)
UPDATED = datetime(2024, 5, 2, 8, 0, tzinfo=timezone.utc)


def make_poem(
    poem_id: int,
    *,
    title: str = "Title",
    text: str = "line one\nline two",
    author_id: int = 1,
    theme_id: int | None = None,
    views: int = 0,
) -> PoemRow:
    return PoemRow(
        id=poem_id,
        title=title,
        text=text,
        author_id=author_id,
        theme_id=theme_id,
        created_at=CREATED,
        updated_at=UPDATED,
        views=views,
    )


def make_author(author_id: int, name: str = "Author") -> AuthorRow:
    return AuthorRow(id=author_id, name=name, bio="bio", photo=None)


def test_chunk_splits_4500_into_2000_2000_500():
    entries = [{"id": i} for i in range(4500)]

    chunks = chunk(entries)

    assert CHUNK_SIZE == 2000
    assert [len(c) for c in chunks] == [2000, 2000, 500]
    assert [e for c in chunks for e in c] == entries


def test_entry_has_exact_keys_and_author_name():
    authors = {7: make_author(7, "Бейтыгъуэн")}
    poems = [make_poem(1, title="Сурэт", author_id=7, theme_id=3)]

    entries = catalog_entries(poems, authors)

    assert len(entries) == 1
    entry = entries[0]
    assert set(entry) == {"id", "title", "authorId", "authorName", "themeId", "lines", "views", "createdAt"}
    assert entry == {
        "id": 1,
        "title": "Сурэт",
        "authorId": 7,
        "authorName": "Бейтыгъуэн",
        "themeId": 3,
        "lines": 2,
        "views": 0,
        "createdAt": CREATED,
    }


def test_line_count_ignores_blank_lines_and_crlf():
    assert line_count("a\r\n\r\nb\nc\r") == 3
    assert line_count("") == 0


def test_line_count_splits_only_on_crlf_lf_and_cr():
    assert line_count("a\nb") == 2
    assert line_count("a\rb") == 2
    assert line_count("a\r\nb") == 2
    # Blank means empty or only spaces and tabs; a lone separator is not a line.
    assert line_count("  \n\t\n \r\n") == 0
    assert line_count("\n\nonly\n\n") == 1
    # Other Unicode separators stay inside their line, as they do for the server and the app.
    assert line_count("a\u2028b\x0bc\x85d") == 1


def test_line_count_counts_a_line_with_indentation():
    assert line_count("  indented\n\tTabbed\nПалочка Ӏ") == 3


def test_catalog_entries_carry_lines_and_views():
    entry = catalog_entries(
        [make_poem(1, text="a\nb", views=7)], {1: make_author(1)}
    )[0]
    assert entry["lines"] == 2 and entry["views"] == 7


def test_catalog_entry_counts_lines_without_blank_ones():
    poems = [make_poem(1, text="a\r\n\r\nb\n\n"), make_poem(2, text="")]

    first, second = catalog_entries(poems, {1: make_author(1)})

    assert first["lines"] == 2
    assert second["lines"] == 0


def test_theme_id_none_is_preserved():
    authors = {1: make_author(1)}
    poems = [make_poem(1, theme_id=None)]

    entry = catalog_entries(poems, authors)[0]

    assert "themeId" in entry
    assert entry["themeId"] is None


def test_entries_are_sorted_by_id_ascending():
    authors = {1: make_author(1)}
    poems = [make_poem(5), make_poem(4130), make_poem(12)]

    entries = catalog_entries(poems, authors)

    assert [e["id"] for e in entries] == [5, 12, 4130]


def test_meta_excludes_authors_without_poems_and_counts_correctly():
    themes = [ThemeRow(id=2, title="Love"), ThemeRow(id=1, title="Nature"), ThemeRow(id=3, title="Empty")]
    authors = {
        9: make_author(9, "Zed"),
        4: make_author(4, "Alpha"),
        6: make_author(6, "No poems"),
    }
    poems = [
        make_poem(1, author_id=9, theme_id=1),
        make_poem(2, author_id=4, theme_id=1),
        make_poem(3, author_id=4, theme_id=2),
        make_poem(4, author_id=4, theme_id=None),
    ]

    meta = meta_document(
        themes, authors, poems, catalog_version=3, chunk_count=1, minimum_app_version="1.2"
    )

    assert meta["authors"] == [
        {"id": 4, "name": "Alpha", "poemsCount": 3},
        {"id": 9, "name": "Zed", "poemsCount": 1},
    ]
    assert meta["themes"] == [
        {"id": 1, "title": "Nature", "poemsCount": 2},
        {"id": 2, "title": "Love", "poemsCount": 1},
        {"id": 3, "title": "Empty", "poemsCount": 0},
    ]
    assert meta["catalogVersion"] == 3
    assert meta["catalogChunks"] == 1
    assert meta["minimumAppVersion"] == "1.2"
    assert set(meta) == {
        "catalogVersion",
        "catalogChunks",
        "authors",
        "themes",
        "nextPoemId",
        "minimumAppVersion",
    }


def test_meta_next_poem_id_is_max_plus_one():
    authors = {1: make_author(1)}
    poems = [make_poem(5), make_poem(4130), make_poem(12)]

    meta = meta_document(
        [], authors, poems, catalog_version=1, chunk_count=1, minimum_app_version=None
    )

    assert meta["nextPoemId"] == 4131
    assert meta["minimumAppVersion"] is None


def test_meta_document_copies_photo_urls():
    authors = {
        1: AuthorRow(id=1, name="А", bio="", photo="https://p/1.jpg"),
        2: AuthorRow(id=2, name="Б", bio="", photo=None),
        3: AuthorRow(id=3, name="В", bio="", photo=""),
    }
    poems = [make_poem(1, author_id=1), make_poem(2, author_id=2), make_poem(3, author_id=3)]

    meta = meta_document(
        [], authors, poems, catalog_version=1, chunk_count=1, minimum_app_version=None
    )

    assert meta["authors"] == [
        {"id": 1, "name": "А", "poemsCount": 1, "photoURL": "https://p/1.jpg"},
        {"id": 2, "name": "Б", "poemsCount": 1},
        {"id": 3, "name": "В", "poemsCount": 1},
    ]


def test_realistic_chunk_fits_firestore_limit():
    title = ("Адыгэ лъэпкъым и таурыхъ " * 3)[:60]
    name = ("Бейтыгъуэн Хьэтэ Борис " * 2)[:30]
    assert len(title) == 60 and len(name) == 30
    authors = {1: make_author(1, name)}
    poems = [make_poem(4000 + i, title=title, theme_id=14) for i in range(2000)]

    entries = catalog_entries(poems, authors)
    first_chunk = chunk(entries)[0]

    assert len(first_chunk) == 2000
    size = len(json.dumps(first_chunk, ensure_ascii=False, default=str).encode())
    assert size < 900_000


def test_poem_document_fields():
    poem = make_poem(4130, title="Сурэт", author_id=7, theme_id=3, views=12)

    doc = poem_document(poem, "Бейтыгъуэн")

    assert doc == {
        "id": 4130,
        "title": "Сурэт",
        "text": "line one\nline two",
        "authorId": 7,
        "authorName": "Бейтыгъуэн",
        "themeId": 3,
        "createdAt": CREATED,
        "updatedAt": UPDATED,
        "submittedBy": None,
        "views": 12,
    }


def test_poem_row_views_default_to_zero():
    assert make_poem(1).views == 0
    assert poem_document(make_poem(1), "A")["views"] == 0


def test_author_document_blank_photo_becomes_null():
    # Django's ImageField(blank=True) without null=True stores '' in Postgres, not NULL.
    blank = AuthorRow(id=9, name="Blank", bio="", photo="")

    assert author_document(blank, poems_count=1)["photoURL"] is None


def test_author_and_theme_documents():
    author = AuthorRow(id=7, name="Name", bio="Bio text", photo="authors/7.jpg")
    no_photo = AuthorRow(id=8, name="Other", bio="", photo=None)

    assert author_document(author, poems_count=12) == {
        "id": 7,
        "name": "Name",
        "bio": "Bio text",
        "photoURL": "authors/7.jpg",
        "poemsCount": 12,
    }
    assert author_document(no_photo, poems_count=0)["photoURL"] is None
    assert theme_document(ThemeRow(id=3, title="Love"), poems_count=5) == {
        "id": 3,
        "title": "Love",
        "poemsCount": 5,
    }
