"""The catalog the picking rules work on, read from `meta/content` and the `catalog/{n}` chunks.

The admin tool's `rebuild` writes them (see wuserade_admin/catalog.py). The server never recounts
lines or views: it trusts the `lines` and `views` on each entry.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from google.cloud.firestore import Client

META_PATH = "meta/content"

# Sorts before every real creation time.
_EPOCH = datetime.fromtimestamp(0, tz=timezone.utc)


@dataclass(frozen=True)
class Entry:
    """One poem of the catalog. `title` is "" for an untitled poem."""

    id: int
    title: str
    author_id: int
    author_name: str
    theme_id: int | None
    lines: int  # non-blank lines of the text
    views: int
    created_at: datetime


@dataclass(frozen=True)
class Poet:
    """One of `meta/content.authors` (only authors with poems are listed)."""

    id: int
    name: str
    poems_count: int
    photo_url: str | None


@dataclass(frozen=True)
class Catalog:
    version: int
    entries: list[Entry]
    poets: list[Poet]


def _entry(raw: dict) -> Entry:
    # Chunks written before the daily discovery have no `lines` or `views`.
    return Entry(
        id=raw["id"],
        title=raw.get("title") or "",
        author_id=raw["authorId"],
        author_name=raw.get("authorName") or "",
        theme_id=raw.get("themeId"),
        lines=raw.get("lines") or 0,
        views=raw.get("views") or 0,
        created_at=raw.get("createdAt") or _EPOCH,
    )


def _poet(raw: dict) -> Poet:
    return Poet(
        id=raw["id"],
        name=raw["name"],
        poems_count=raw.get("poemsCount") or 0,
        photo_url=raw.get("photoURL") or None,
    )


def load_catalog(db: Client) -> Catalog:
    """Read `meta/content` and every chunk it lists, joined in index order.

    A ValueError says what is wrong when there is no `meta/content`, a chunk is missing, or a chunk
    is of another version than `meta/content` (a `rebuild` is half way; try again later). The app
    refuses the same.
    """
    meta_snapshot = db.document(META_PATH).get()
    if not meta_snapshot.exists:
        raise ValueError(f"{META_PATH} does not exist; run the admin tool's rebuild")
    meta = meta_snapshot.to_dict()
    version = meta["catalogVersion"]

    entries: list[Entry] = []
    for index in range(meta["catalogChunks"]):
        path = f"catalog/{index}"
        snapshot = db.document(path).get()
        if not snapshot.exists:
            raise ValueError(f"{path} does not exist, but {META_PATH} lists {meta['catalogChunks']} chunks")
        chunk = snapshot.to_dict()
        if chunk.get("version") != version:
            raise ValueError(
                f"{path} is at version {chunk.get('version')}, but {META_PATH} is at {version}; "
                "a rebuild is probably running"
            )
        entries.extend(_entry(raw) for raw in chunk.get("entries", []))

    return Catalog(version=version, entries=entries, poets=[_poet(raw) for raw in meta.get("authors", [])])
