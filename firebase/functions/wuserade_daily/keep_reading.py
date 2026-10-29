"""Keep-reading suggestions: "more by this poet" and "you might also like".

`rank` orders candidates from the catalog alone. Only then does `keep_reading` check those few
candidates (at most 25) against the caller's `users/{uid}/reads`, so a reader's whole history is
never listed: first the 5 that would be shown, then the rest of a list only if one of those is read.
`choose` takes the first unread ones.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Callable

from wuserade_daily.catalog import META_PATH, Catalog, Entry, load_catalog

log = logging.getLogger(__name__)

if TYPE_CHECKING:
    from google.cloud.firestore import Client

POET_CANDIDATES = 10
SIMILAR_CANDIDATES = 5  # per list: theme, liked, length
POET_SHOWN = 3
SIMILAR_SHOWN = 2
LENGTH_WINDOW = 3  # lines either way
LIKES_READ = 20


class PoemNotFound(ValueError):
    """The poem is not in the catalog."""


@dataclass(frozen=True)
class Candidates:
    """Poem ids, best first. No id is in two lists."""

    poet: list[int]
    theme: list[int]
    liked: list[int]
    length: list[int]


def _most_read(entries) -> list[Entry]:
    return sorted(entries, key=lambda e: (-e.views, e.id))


def rank(poem_id: int, catalog: Catalog, liked_author_ids: set[int]) -> Candidates:
    poem = next((e for e in catalog.entries if e.id == poem_id), None)
    if poem is None:
        raise PoemNotFound(poem_id)
    others = [e for e in catalog.entries if e.id != poem_id]
    taken: set[int] = set()

    def pick(entries, limit: int) -> list[int]:
        ids = [e.id for e in _most_read(e for e in entries if e.id not in taken)][:limit]
        taken.update(ids)
        return ids

    by_other_poets = [e for e in others if e.author_id != poem.author_id]
    return Candidates(
        poet=pick((e for e in others if e.author_id == poem.author_id), POET_CANDIDATES),
        theme=pick(
            (e for e in by_other_poets if poem.theme_id is not None and e.theme_id == poem.theme_id),
            SIMILAR_CANDIDATES,
        ),
        liked=pick((e for e in by_other_poets if e.author_id in liked_author_ids), SIMILAR_CANDIDATES),
        length=pick(
            (e for e in by_other_poets if abs(e.lines - poem.lines) <= LENGTH_WINDOW), SIMILAR_CANDIDATES
        ),
    )


def choose(c: Candidates, read_ids: set[int]) -> tuple[list[int], list[int]]:
    """The first 3 unread poet poems, and up to 2 unread others from theme, then liked, then length."""
    poet = [i for i in c.poet if i not in read_ids][:POET_SHOWN]
    similar = [i for i in (*c.theme, *c.liked, *c.length) if i not in read_ids][:SIMILAR_SHOWN]
    return poet, similar


def _liked_author_ids(db: Client, uid: str) -> set[int]:
    query = (
        db.collection(f"users/{uid}/likes").order_by("likedAt", direction="DESCENDING").limit(LIKES_READ)
    )
    return {d.get("authorId") for d in query.stream() if d.get("authorId") is not None}


def _read_among(db: Client, uid: str, ids: list[int]) -> set[int]:
    """The poems among `ids` the caller has read, in one batched read (a missing document still counts)."""
    if not ids:
        return set()
    refs = [db.document(f"users/{uid}/reads/{i}") for i in ids]
    # get_all does not return snapshots in the order of the refs: key on the snapshot's own id.
    return {int(snap.id) for snap in db.get_all(refs) if snap.exists}


def keep_reading(db: Client, uid: str, poem_id: int, catalog: Catalog) -> dict:
    """The suggestions for the caller finishing `poem_id`, as plain JSON-serialisable data."""
    candidates = rank(poem_id, catalog, set())
    if len(candidates.theme) < SIMILAR_CANDIDATES:
        # Liked poets only matter when the theme cannot fill the list; re-rank with them.
        candidates = rank(poem_id, catalog, _liked_author_ids(db, uid))

    poet = list(candidates.poet)
    similar = [*candidates.theme, *candidates.liked, *candidates.length]
    # Two rounds, with the same result as checking every candidate: first only the poems that would be shown
    # if none were read. A list whose shown poems are all unread is settled; only a list with a read one needs
    # the rest of its candidates checked.
    read_ids = _read_among(db, uid, [*poet[:POET_SHOWN], *similar[:SIMILAR_SHOWN]])
    rest = []
    if read_ids.intersection(poet[:POET_SHOWN]):
        rest += poet[POET_SHOWN:]
    if read_ids.intersection(similar[:SIMILAR_SHOWN]):
        rest += similar[SIMILAR_SHOWN:]
    read_ids |= _read_among(db, uid, rest)

    poet_ids, similar_ids = choose(candidates, read_ids)
    by_id = {e.id: e for e in catalog.entries}
    return {
        "poet": [{"id": i, "title": by_id[i].title} for i in poet_ids],
        "similar": [
            {"id": i, "title": by_id[i].title, "authorId": by_id[i].author_id, "authorName": by_id[i].author_name}
            for i in similar_ids
        ],
    }


class CatalogCache:
    """Keeps the last catalog, re-loaded when `meta/content.catalogVersion` changes. The version is read at
    most once every `CHECK_INTERVAL` seconds per instance, so a new catalog is served within a minute."""

    CHECK_INTERVAL = 60.0

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._catalog: Catalog | None = None
        self._clock = clock
        self._checked_at: float | None = None

    def get(self, db: Client) -> Catalog:
        """The catalog for the current version. While a rebuild makes loading fail (ValueError), the
        previous catalog is served and the next call tries again; with none cached the error is raised."""
        cached = self._catalog
        now = self._clock()
        if cached is not None and self._checked_at is not None and now - self._checked_at < self.CHECK_INTERVAL:
            return cached
        snapshot = db.document(META_PATH).get()
        version = snapshot.to_dict().get("catalogVersion") if snapshot.exists else None
        if cached is not None and version is not None and version == cached.version:
            self._checked_at = now
            return cached
        try:
            loaded = load_catalog(db)
        except ValueError:
            if cached is None:
                raise
            log.warning("catalog reload failed; serving version %s", cached.version, exc_info=True)
            return cached  # not marked checked: the next call tries again
        self._catalog = loaded
        self._checked_at = now
        return loaded
