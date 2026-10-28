"""Reads the old Django/Postgres content. Read-only: this module never writes to Postgres.

`read_postgres` is a thin SQL reader. The row mapping lives in small pure helpers so it can
be tested without a database. The old `poems_poem.theme` CharField is ignored; the app uses
the `category` foreign key, which is mapped to `theme_id`.
"""

from __future__ import annotations

from datetime import datetime, timezone

import psycopg

from .models import AuthorRow, PoemRow, ThemeRow

THEMES_SQL = "SELECT id, title FROM poems_theme ORDER BY id"
AUTHORS_SQL = "SELECT id, name, bio, photo FROM poems_author ORDER BY id"
POEMS_SQL = (
    "SELECT id, title, text, author_id, category_id, created_at, updated_at "
    "FROM poems_poem ORDER BY id"
)


def to_utc(value: datetime) -> datetime:
    """Timezone-aware UTC. A naive value is taken to be UTC (Django runs with TIME_ZONE='UTC')."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def theme_from_row(row: tuple) -> ThemeRow:
    theme_id, title = row
    return ThemeRow(id=theme_id, title=title)


def author_from_row(row: tuple) -> AuthorRow:
    author_id, name, bio, photo = row
    return AuthorRow(id=author_id, name=name, bio=bio or "", photo=photo)


def poem_from_row(row: tuple) -> PoemRow:
    poem_id, title, text, author_id, category_id, created_at, updated_at = row
    return PoemRow(
        id=poem_id,
        title=title,
        text=text,
        author_id=author_id,
        theme_id=category_id,
        created_at=to_utc(created_at),
        updated_at=to_utc(updated_at),
    )


def read_postgres(dsn: str) -> tuple[list[ThemeRow], list[AuthorRow], list[PoemRow]]:
    """Read every theme, author and poem, each list ordered by id."""
    try:
        with psycopg.connect(dsn) as conn:
            conn.read_only = True
            themes = [theme_from_row(row) for row in conn.execute(THEMES_SQL)]
            authors = [author_from_row(row) for row in conn.execute(AUTHORS_SQL)]
            poems = [poem_from_row(row) for row in conn.execute(POEMS_SQL)]
    except psycopg.Error as error:
        raise ValueError(f"could not read Postgres: {error}") from error
    return themes, authors, poems
