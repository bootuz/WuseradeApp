"""Pure builders that turn database rows into Firestore document dicts.

Nothing here talks to Postgres or Firestore. Datetimes are passed through
untouched (timezone-aware UTC), so firebase-admin stores them as Timestamps.
Field names are exactly what the iOS app decodes.
"""

from __future__ import annotations

from collections import Counter

from .models import AuthorRow, PoemRow, ThemeRow

# 2,000 entries of ~300 bytes each stay well under Firestore's 1 MiB document limit.
CHUNK_SIZE = 2000


def catalog_entries(poems: list[PoemRow], authors: dict[int, AuthorRow]) -> list[dict]:
    """One lightweight catalog entry per poem, sorted by poem id ascending."""
    return [
        {
            "id": p.id,
            "title": p.title,
            "authorId": p.author_id,
            "authorName": authors[p.author_id].name,
            "themeId": p.theme_id,
            "createdAt": p.created_at,
        }
        for p in sorted(poems, key=lambda p: p.id)
    ]


def chunk(entries: list[dict], size: int = CHUNK_SIZE) -> list[list[dict]]:
    """Split entries into consecutive chunks of at most `size`."""
    return [entries[i : i + size] for i in range(0, len(entries), size)]


def poem_document(p: PoemRow, author_name: str) -> dict:
    """The `poems/{id}` document. `submittedBy` is reserved for future user poems."""
    return {
        "id": p.id,
        "title": p.title,
        "text": p.text,
        "authorId": p.author_id,
        "authorName": author_name,
        "themeId": p.theme_id,
        "createdAt": p.created_at,
        "updatedAt": p.updated_at,
        "submittedBy": None,
    }


def author_document(a: AuthorRow, poems_count: int) -> dict:
    """The `authors/{id}` document.

    Django stores a missing photo as '' (ImageField blank=True, not null), so a
    blank value is normalized to None; the app must see null, not an empty URL.
    """
    return {
        "id": a.id,
        "name": a.name,
        "bio": a.bio,
        "photoURL": a.photo or None,
        "poemsCount": poems_count,
    }


def theme_document(t: ThemeRow, poems_count: int) -> dict:
    """The `themes/{id}` document."""
    return {"id": t.id, "title": t.title, "poemsCount": poems_count}


def _meta_author(a: AuthorRow, poems_count: int) -> dict:
    """An entry of `meta/content.authors`; `photoURL` is left out when there is no photo."""
    entry = {"id": a.id, "name": a.name, "poemsCount": poems_count}
    if a.photo:
        entry["photoURL"] = a.photo
    return entry


def meta_document(
    themes: list[ThemeRow],
    authors: dict[int, AuthorRow],
    poems: list[PoemRow],
    catalog_version: int,
    chunk_count: int,
    minimum_app_version: str | None,
) -> dict:
    """The `meta/content` document.

    `authors` maps author id to row and may contain authors without poems; only
    those with at least one poem are listed. Both lists are sorted by id. An author
    entry carries `photoURL` only when the author has a photo.
    """
    per_author = Counter(p.author_id for p in poems)
    per_theme = Counter(p.theme_id for p in poems if p.theme_id is not None)
    return {
        "catalogVersion": catalog_version,
        "catalogChunks": chunk_count,
        "authors": [
            _meta_author(a, per_author[a.id])
            for a in sorted(authors.values(), key=lambda a: a.id)
            if per_author[a.id] > 0
        ],
        "themes": [
            {"id": t.id, "title": t.title, "poemsCount": per_theme[t.id]}
            for t in sorted(themes, key=lambda t: t.id)
        ],
        "nextPoemId": max((p.id for p in poems), default=0) + 1,
        "minimumAppVersion": minimum_app_version,
    }
