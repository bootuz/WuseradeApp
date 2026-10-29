"""Plain rows read from the old Postgres database (or loaded back from Firestore)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class ThemeRow:
    id: int
    title: str


@dataclass(frozen=True)
class AuthorRow:
    id: int
    name: str
    bio: str
    photo: str | None


@dataclass(frozen=True)
class PoemRow:
    id: int
    title: str
    text: str
    author_id: int
    theme_id: int | None
    created_at: datetime
    updated_at: datetime
    # Reads counted on the old site (Django's poems_poem.views). Poems added since have none.
    views: int = 0
