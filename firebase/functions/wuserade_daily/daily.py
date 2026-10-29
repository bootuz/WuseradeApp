"""The `daily/{YYYY-MM-DD}` documents: written ahead by the scheduled function, re-synced by `rebuild`.

A day's document copies everything the app shows (titles, texts, the poet's top poems), so the
app reads one document. The scheduler writes the days from yesterday to a week ahead, so every
time zone finds its date. A written day is never re-picked on a schedule; `resync_days` only
brings it up to date with corrections and removals made in the content since.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import TYPE_CHECKING

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from .catalog import Catalog, Entry, Poet, load_catalog
from .picks import DayPicks, pick_day, pick_poem, pick_poet, pick_short_poem, top_poems

if TYPE_CHECKING:
    from google.cloud.firestore import Client

COLLECTION = "daily"
HISTORY_DAYS = 365
DAYS_BEHIND = 1
DAYS_AHEAD = 7


def daily_document(day: date, picks: DayPicks, catalog: Catalog, texts: dict[int, str]) -> dict:
    """The document of `day`, exactly as the spec shapes it. `texts` holds the two poems' texts."""
    entries = {e.id: e for e in catalog.entries}
    poets = {p.id: p for p in catalog.poets}
    return {
        "date": day.isoformat(),
        "poem": _poem(entries[picks.poem_id], texts[picks.poem_id]),
        "shortPoem": _poem(entries[picks.short_poem_id], texts[picks.short_poem_id]),
        "poet": _poet(poets[picks.poet_id], catalog),
        "createdAt": firestore.SERVER_TIMESTAMP,
    }


def _poem(entry: Entry, text: str) -> dict:
    return {
        "id": entry.id,
        "title": entry.title,
        "authorId": entry.author_id,
        "authorName": entry.author_name,
        "text": text,
    }


def _poet(poet: Poet, catalog: Catalog) -> dict:
    data = {
        "id": poet.id,
        "name": poet.name,
        "poemsCount": poet.poems_count,
        "topPoems": [{"id": e.id, "title": e.title} for e in top_poems(catalog, poet.id)],
    }
    if poet.photo_url:
        data["photoURL"] = poet.photo_url
    return data


def _id_filter(db: Client, op: str, day_id: str) -> FieldFilter:
    """A filter on the document id of `daily/{day_id}` (the day ids sort like the dates)."""
    return FieldFilter("__name__", op, db.document(f"{COLLECTION}/{day_id}"))


def read_history(db: Client, before: date, days: int = HISTORY_DAYS) -> list[DayPicks]:
    """The picks of the daily documents dated in `[before - days, before)`, newest first."""
    query = (
        db.collection(COLLECTION)
        .where(filter=_id_filter(db, ">=", (before - timedelta(days=days)).isoformat()))
        .where(filter=_id_filter(db, "<", before.isoformat()))
        .order_by("__name__")
    )
    # Ascending, then reversed: the emulator has no descending scan on the document id.
    return [_stored_picks(snapshot.to_dict()) for snapshot in reversed(list(query.stream()))]


def _stored_picks(doc: dict) -> DayPicks:
    return DayPicks(poem_id=doc["poem"]["id"], short_poem_id=doc["shortPoem"]["id"], poet_id=doc["poet"]["id"])


def _texts(db: Client, ids: set[int]) -> dict[int, str]:
    """`poems/{id}.text` for the ids that exist."""
    refs = [db.document(f"poems/{poem_id}") for poem_id in sorted(ids)]
    return {int(s.id): (s.to_dict() or {}).get("text", "") for s in db.get_all(refs) if s.exists}


def write_missing_days(db: Client, today: date, catalog: Catalog | None = None) -> list[str]:
    """Write the days from `today - 1` to `today + 7` that have no document; return the dates written.

    `today` is the UTC date. Days are written in date order, and each one's history is read from
    Firestore, so it includes the days written just before it.
    """
    catalog = catalog if catalog is not None else load_catalog(db)
    written: list[str] = []
    for offset in range(-DAYS_BEHIND, DAYS_AHEAD + 1):
        day = today + timedelta(days=offset)
        ref = db.document(f"{COLLECTION}/{day.isoformat()}")
        if ref.get().exists:
            continue
        picks = pick_day(day, catalog, read_history(db, before=day))
        texts = _texts(db, {picks.poem_id, picks.short_poem_id})
        for poem_id in (picks.poem_id, picks.short_poem_id):
            if poem_id not in texts:
                raise ValueError(f"poems/{poem_id} does not exist, but the catalog lists it")
        ref.set(daily_document(day, picks, catalog, texts))
        written.append(day.isoformat())
    return written


def resync_days(db: Client, today: date, catalog: Catalog) -> list[str]:
    """Bring the daily documents from `today - 1` onward up to date with the content.

    Corrected titles, names, texts, poems counts, photos and top poems are copied again. A slot
    whose poem or poet no longer exists in `catalog` is picked again with that slot's rules alone,
    the other two slots staying as they are. Only documents that change are written (their
    `createdAt` is kept). Returns the dates written.
    """
    start = (today - timedelta(days=DAYS_BEHIND)).isoformat()
    snapshots = list(
        db.collection(COLLECTION).where(filter=_id_filter(db, ">=", start)).order_by("__name__").stream()
    )
    entries = {e.id: e for e in catalog.entries}
    poets = {p.id: p for p in catalog.poets}

    stored_picks = {s.id: _stored_picks(s.to_dict()) for s in snapshots}
    texts = _texts(db, {i for p in stored_picks.values() for i in (p.poem_id, p.short_poem_id)})

    changed: list[str] = []
    for snapshot in snapshots:
        stored = snapshot.to_dict()
        day = date.fromisoformat(snapshot.id)
        picks = _repick(db, day, catalog, entries, poets, stored_picks[snapshot.id])
        # A poem without a text document keeps the text it had.
        day_texts = {
            poem_id: texts.get(poem_id, _stored_text(stored, poem_id))
            for poem_id in (picks.poem_id, picks.short_poem_id)
        }
        fresh = daily_document(day, picks, catalog, day_texts)
        if "createdAt" in stored:
            fresh["createdAt"] = stored["createdAt"]
        if fresh != stored:
            snapshot.reference.set(fresh)
            changed.append(snapshot.id)
    return changed


def _stored_text(stored: dict, poem_id: int) -> str:
    for slot in ("poem", "shortPoem"):
        if stored[slot]["id"] == poem_id:
            return stored[slot].get("text", "")
    return ""


def _repick(
    db: Client,
    day: date,
    catalog: Catalog,
    entries: dict[int, Entry],
    poets: dict[int, Poet],
    picks: DayPicks,
) -> DayPicks:
    """`picks` with each slot whose poem or poet is gone picked again; the others stay."""
    poem_gone = picks.poem_id not in entries
    short_gone = picks.short_poem_id not in entries
    poet_gone = picks.poet_id not in poets
    if not (poem_gone or short_gone or poet_gone):
        return picks
    history = read_history(db, before=day)
    if poem_gone:
        poem = pick_poem(day, catalog, history, avoid_id=None if short_gone else picks.short_poem_id)
    else:
        poem = entries[picks.poem_id]
    short_poem = pick_short_poem(day, catalog, history, poem) if short_gone else entries[picks.short_poem_id]
    poet = pick_poet(day, catalog, history, poem, short_poem) if poet_gone else poets[picks.poet_id]
    return DayPicks(poem_id=poem.id, short_poem_id=short_poem.id, poet_id=poet.id)
