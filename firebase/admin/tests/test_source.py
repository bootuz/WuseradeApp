"""Row mapping for the Postgres reader. read_postgres itself is a thin SQL reader and is not tested here."""

from datetime import datetime, timedelta, timezone

from wuserade_admin.models import AuthorRow, PoemRow, ThemeRow
from wuserade_admin.source import POEMS_SQL, author_from_row, poem_from_row, theme_from_row, to_utc

UTC = timezone.utc


def test_theme_and_author_rows():
    assert theme_from_row((3, "Лъагъуныгъэ")) == ThemeRow(id=3, title="Лъагъуныгъэ")
    assert author_from_row((7, "Name", "Bio", "photos/a.jpg")) == AuthorRow(
        id=7, name="Name", bio="Bio", photo="photos/a.jpg"
    )


def test_author_blank_photo_and_missing_bio():
    # Django's ImageField(blank=True) stores '' (the document builder turns it into null).
    assert author_from_row((8, "Name", "", "")).photo == ""
    assert author_from_row((9, "Name", None, None)) == AuthorRow(id=9, name="Name", bio="", photo=None)


def test_poem_row_maps_category_id_to_theme_id():
    created = datetime(2024, 3, 1, 12, 0, tzinfo=UTC)
    updated = datetime(2024, 5, 2, 8, 0, tzinfo=UTC)

    poem = poem_from_row((4130, "Title", "line\r\nline", 7, 12, created, updated, 321))

    assert poem == PoemRow(
        id=4130,
        title="Title",
        text="line\r\nline",
        author_id=7,
        theme_id=12,
        created_at=created,
        updated_at=updated,
        views=321,
    )


def test_poem_views_is_the_last_selected_column():
    assert POEMS_SQL.startswith("SELECT id, title, text, author_id, category_id, created_at, updated_at, views ")
    assert "FROM poems_poem" in POEMS_SQL


def test_poem_with_a_null_views_column_counts_zero():
    now = datetime(2024, 3, 1, tzinfo=UTC)

    assert poem_from_row((1, "T", "x", 1, None, now, now, None)).views == 0


def test_poem_without_category_has_no_theme():
    now = datetime(2024, 3, 1, tzinfo=UTC)

    assert poem_from_row((1, "T", "x", 1, None, now, now, 0)).theme_id is None


def test_datetimes_become_timezone_aware_utc():
    plus_three = timezone(timedelta(hours=3))
    aware = datetime(2024, 3, 1, 15, 0, tzinfo=plus_three)
    naive = datetime(2024, 3, 1, 12, 0)

    assert to_utc(aware) == datetime(2024, 3, 1, 12, 0, tzinfo=UTC)
    assert to_utc(aware).utcoffset() == timedelta(0)
    assert to_utc(naive) == datetime(2024, 3, 1, 12, 0, tzinfo=UTC)
    assert to_utc(naive).tzinfo is not None

    poem = poem_from_row((1, "T", "x", 1, None, aware, naive, 0))
    assert poem.created_at.utcoffset() == timedelta(0)
    assert poem.updated_at.utcoffset() == timedelta(0)
