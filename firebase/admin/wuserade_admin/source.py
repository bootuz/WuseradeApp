"""Reads the old Django/Postgres content. Read-only: this module never writes to Postgres.

`read_postgres` is a thin SQL reader. The row mapping lives in small pure helpers so it can
be tested without a database. The old `poems_poem.theme` CharField is ignored; the app uses
the `category` foreign key, which is mapped to `theme_id`.
"""

from __future__ import annotations

import re
from datetime import datetime, timezone
from urllib.parse import quote, unquote, urlsplit

import psycopg

from .models import AuthorRow, PoemRow, ThemeRow

INVALID_URL_MESSAGE = (
    "could not read Postgres: the database URL is not valid. Details are withheld so that a typo "
    "cannot print the password. Copy the External Database URL from the Render dashboard "
    "(it starts with postgresql:// or postgres://)."
)

# user:password@ inside any text (also in malformed URLs); the password runs to the last '@'
# of the token, so a raw '@' in a password does not leak its tail.
_USERINFO = re.compile(r"""([^/\s:@'"]*):([^\s'"]*)@""")
# password=... in key/value connection strings, bare or single-quoted.
_PASSWORD_PARAM = re.compile(r"""(password\s*=\s*)('(?:[^'\\]|\\.)*'|\S+)""", re.IGNORECASE)

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


def mask_passwords(text: str) -> str:
    """Hide anything that looks like a password in `text`: user:password@ and password=..."""
    text = _USERINFO.sub(r"\1:<password>@", text)
    return _PASSWORD_PARAM.sub(r"\1<password>", text)


def _passwords_in(dsn: str) -> set[str]:
    """Every password-like fragment of `dsn`, in raw, percent-decoded and percent-encoded form."""
    found = set()
    for match in _USERINFO.finditer(dsn):
        # For "scheme://user:pw@" the match is "scheme" + ":" + "//user:pw"; keep every tail of it.
        tail = match.group(2)
        found |= {tail, tail.rsplit("/", 1)[-1], tail.rsplit("/", 1)[-1].split(":", 1)[-1]}
    found |= {match.group(2).strip("'") for match in _PASSWORD_PARAM.finditer(dsn)}
    try:
        found.add(urlsplit(dsn).password or "")
    except ValueError:
        pass
    found |= {unquote(p) for p in found} | {quote(p, safe="") for p in found}
    return {p for p in found if p}


def redact_dsn(text: str, dsn: str) -> str:
    """`text` with the URL and its password removed, for error messages that may quote either."""
    text = text.replace(dsn, "<dsn>")
    for password in sorted(_passwords_in(dsn), key=len, reverse=True):
        text = text.replace(password, "<password>")
    return mask_passwords(text)


def read_postgres(dsn: str) -> tuple[list[ThemeRow], list[AuthorRow], list[PoemRow]]:
    """Read every theme, author and poem, each list ordered by id.

    Failures are raised as ValueError with a message that never contains the URL or its
    password, and with the original exception dropped (`from None`), because psycopg echoes
    the URL it could not parse and a traceback would print that too.
    """
    try:
        with psycopg.connect(dsn) as conn:
            conn.read_only = True
            theme_rows = conn.execute(THEMES_SQL).fetchall()
            author_rows = conn.execute(AUTHORS_SQL).fetchall()
            poem_rows = conn.execute(POEMS_SQL).fetchall()
    except psycopg.ProgrammingError as error:
        if error.sqlstate is None:
            # Raised by psycopg/libpq itself while parsing the URL: the text quotes the URL.
            raise ValueError(INVALID_URL_MESSAGE) from None
        raise ValueError(f"could not read Postgres: {redact_dsn(str(error), dsn)}") from None
    except psycopg.Error as error:
        raise ValueError(f"could not read Postgres: {redact_dsn(str(error), dsn)}") from None
    except Exception as error:
        raise ValueError(
            f"could not read Postgres: unexpected {type(error).__name__} "
            "(details withheld in case they contain the database URL)"
        ) from None
    return (
        [theme_from_row(row) for row in theme_rows],
        [author_from_row(row) for row in author_rows],
        [poem_from_row(row) for row in poem_rows],
    )
