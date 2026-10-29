"""Firestore reads and writes for the admin tool (Firebase Admin SDK).

Security rules do not apply to the Admin SDK, so this is the only writer of content
(`poems`, `authors`, `themes`, `catalog`, `meta`). Credentials come from Application
Default Credentials; with FIRESTORE_EMULATOR_HOST set, the client talks to the emulator
(project `demo-wuserade`) with no credentials at all.
"""

from __future__ import annotations

import json
import os
import re
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import firestore
from google.auth.credentials import AnonymousCredentials
from google.auth.exceptions import DefaultCredentialsError

from .catalog import (
    author_document,
    catalog_entries,
    chunk,
    meta_document,
    poem_document,
    theme_document,
)
from .models import AuthorRow, PoemRow, ThemeRow

PROJECT_ID = "wuserade"
EMULATOR_PROJECT_ID = "demo-wuserade"

# Firestore allows at most 500 writes in one batch.
BATCH_LIMIT = 500

# Firestore rejects documents of 1 MiB or more. Stay well under that.
MAX_CHUNK_BYTES = 900_000

META_PATH = "meta/content"

_VERSION_PATTERN = re.compile(r"\d+(\.\d+)*")


class ChunkTooLargeError(ValueError):
    """A catalog chunk would be too big for one Firestore document."""


@dataclass(frozen=True)
class RebuildResult:
    catalog_version: int
    chunks: int
    poems: int
    authors_with_poems: int
    themes: int


def connect() -> firestore.Client:
    """A Firestore client: the emulator if FIRESTORE_EMULATOR_HOST is set, else project `wuserade`."""
    if os.environ.get("FIRESTORE_EMULATOR_HOST"):
        return firestore.Client(project=EMULATOR_PROJECT_ID, credentials=AnonymousCredentials())
    try:
        try:
            app = firebase_admin.get_app()
        except ValueError:
            app = firebase_admin.initialize_app(options={"projectId": PROJECT_ID})
        return firestore.client(app)
    except DefaultCredentialsError as error:
        raise ValueError(
            "no Google credentials found; run 'gcloud auth application-default login' "
            f"({error})"
        ) from error


# ---------------------------------------------------------------- reading


def _load(collection, build) -> list[tuple]:
    """(row, raw document dict) for every document of `collection`, ordered by id."""
    rows = []
    for snapshot in collection.stream():
        data = snapshot.to_dict()
        path = snapshot.reference.path
        try:
            doc_id = int(snapshot.id)
        except ValueError:
            raise ValueError(f"{path}: the document id is not a number") from None
        try:
            if data["id"] != doc_id:
                raise ValueError(f"{path}: the id field ({data['id']!r}) does not match the document id")
            rows.append((build(doc_id, data), data))
        except KeyError as missing:
            raise ValueError(f"{path} is missing the field {missing.args[0]!r}") from None
    return sorted(rows, key=lambda pair: pair[0].id)


def _read_content(db) -> tuple[list[ThemeRow], list[AuthorRow], list[PoemRow], dict[int, object]]:
    """Like load_content, plus the authorName currently stored on each poem document."""
    themes = _load(db.collection("themes"), lambda i, d: ThemeRow(id=i, title=d["title"]))
    authors = _load(
        db.collection("authors"),
        lambda i, d: AuthorRow(id=i, name=d["name"], bio=d.get("bio", ""), photo=d.get("photoURL")),
    )
    poems = _load(
        db.collection("poems"),
        lambda i, d: PoemRow(
            id=i,
            title=d["title"],
            text=d["text"],
            author_id=d["authorId"],
            theme_id=d.get("themeId"),
            created_at=d["createdAt"],
            updated_at=d["updatedAt"],
        ),
    )
    stored_author_names = {poem.id: data.get("authorName") for poem, data in poems}
    return (
        [theme for theme, _ in themes],
        [author for author, _ in authors],
        [poem for poem, _ in poems],
        stored_author_names,
    )


def load_content(db) -> tuple[list[ThemeRow], list[AuthorRow], list[PoemRow]]:
    """Read every theme, author and poem back from Firestore, each list ordered by id."""
    themes, authors, poems, _ = _read_content(db)
    return themes, authors, poems


def count_documents(db) -> dict[str, int]:
    """Number of documents in `themes`, `authors` and `poems`."""
    return {
        name: db.collection(name).count().get()[0][0].value
        for name in ("themes", "authors", "poems")
    }


# ---------------------------------------------------------------- writing


def _check_references(authors: dict[int, AuthorRow], poems: list[PoemRow]) -> None:
    for p in poems:
        if p.author_id not in authors:
            raise ValueError(f"poems/{p.id} references author {p.author_id}, which does not exist")


def _poem_counts(poems: list[PoemRow]) -> tuple[Counter, Counter]:
    per_author = Counter(p.author_id for p in poems)
    per_theme = Counter(p.theme_id for p in poems if p.theme_id is not None)
    return per_author, per_theme


def _commit(db, writes: list[tuple], *, update: bool = False, merge: bool = False) -> None:
    """Apply (ref, data) pairs in batches of at most BATCH_LIMIT.

    `set` replaces each document by default. `merge=True` sets only the fields in `data` and
    keeps every other stored field. `update=True` updates fields of existing documents. The
    last two are alternatives.
    """
    if update and merge:
        raise ValueError("update and merge cannot be combined")
    for start in range(0, len(writes), BATCH_LIMIT):
        batch = db.batch()
        for ref, data in writes[start : start + BATCH_LIMIT]:
            if update:
                batch.update(ref, data)
            elif merge:
                batch.set(ref, data, merge=True)
            else:
                batch.set(ref, data)
        batch.commit()


def _author_write(a: AuthorRow, poems_count: int) -> dict:
    """`author_document` without a blank `photoURL`, to be merged into the stored document."""
    data = author_document(a, poems_count)
    if not data["photoURL"]:
        del data["photoURL"]
    return data


def upsert_content(
    db, themes: list[ThemeRow], authors: list[AuthorRow], poems: list[PoemRow]
) -> None:
    """Write themes, authors and poems by id. Safe to run again with the same rows.

    Author names are copied onto the poems. Counts are computed from the rows given; `rebuild`
    recomputes them from what is in Firestore.

    Author documents are merged, not replaced, and a blank Django photo leaves out `photoURL`,
    so a photo the owner approved in Firestore is never overwritten.
    """
    by_id = {a.id: a for a in authors}
    _check_references(by_id, poems)
    per_author, per_theme = _poem_counts(poems)
    _commit(
        db,
        [(db.collection("themes").document(str(t.id)), theme_document(t, per_theme[t.id])) for t in themes],
    )
    _commit(
        db,
        [(db.collection("authors").document(str(a.id)), _author_write(a, per_author[a.id])) for a in authors],
        merge=True,
    )
    _commit(
        db,
        [
            (db.collection("poems").document(str(p.id)), poem_document(p, by_id[p.author_id].name))
            for p in poems
        ],
    )


def check_chunk_sizes(chunks: list[list[dict]], limit: int | None = None) -> None:
    """Raise ChunkTooLargeError if any chunk is about `limit` bytes (default MAX_CHUNK_BYTES) or more."""
    limit = MAX_CHUNK_BYTES if limit is None else limit
    for index, entries in enumerate(chunks):
        size = len(json.dumps(entries, ensure_ascii=False, default=str).encode())
        if size >= limit:
            raise ChunkTooLargeError(
                f"catalog chunk {index} is about {size:,} bytes, over the {limit:,} byte limit "
                "(Firestore documents must stay under 1 MiB); lower catalog.CHUNK_SIZE"
            )


def rebuild(db, minimum_app_version: str | None = None) -> RebuildResult:
    """Make the derived data match the content in Firestore, e.g. after edits in the console.

    Recomputes `poemsCount` on authors and themes, refreshes the author name copied onto each
    poem (`poems/{id}.authorName`) wherever it differs from `authors/{authorId}.name`, and
    rebuilds the catalog chunks and `meta/content`.

    `minimum_app_version`: None keeps the value already in `meta/content` (None if there is no
    meta yet); "" clears it; any other string sets it.

    Everything is checked before the first write. Writes then go in this order, so the app
    never sees a catalogVersion whose chunks are not written yet: author and theme counts and
    changed poem author names (batches of at most 500, only documents that differ), catalog
    chunks, stale chunks removed, `meta/content` last.
    """
    if minimum_app_version and not _VERSION_PATTERN.fullmatch(minimum_app_version):
        raise ValueError(
            f"minimum_app_version {minimum_app_version!r} must look like 1.5 or 1.5.1 "
            "(use an empty string to clear it)"
        )

    themes, authors, poems, stored_author_names = _read_content(db)
    by_id = {a.id: a for a in authors}
    _check_references(by_id, poems)

    previous = db.document(META_PATH).get().to_dict() or {}
    version = previous.get("catalogVersion", 0) + 1
    if minimum_app_version is None:
        minimum = previous.get("minimumAppVersion")
    else:
        minimum = minimum_app_version or None

    chunks = chunk(catalog_entries(poems, by_id))
    check_chunk_sizes(chunks)
    meta = meta_document(themes, by_id, poems, version, len(chunks), minimum)
    # Never hand out an id again, even if the poem that held it was deleted: likes refer to ids.
    meta["nextPoemId"] = max(meta["nextPoemId"], previous.get("nextPoemId", 1))

    per_author, per_theme = _poem_counts(poems)
    _commit(
        db,
        [
            *((db.collection("authors").document(str(a.id)), {"poemsCount": per_author[a.id]}) for a in authors),
            *((db.collection("themes").document(str(t.id)), {"poemsCount": per_theme[t.id]}) for t in themes),
            # Only poems whose copied author name is out of date or missing are written.
            *(
                (db.collection("poems").document(str(p.id)), {"authorName": by_id[p.author_id].name})
                for p in poems
                if stored_author_names[p.id] != by_id[p.author_id].name
            ),
        ],
        update=True,
    )

    catalog = db.collection("catalog")
    for index, entries in enumerate(chunks):
        catalog.document(str(index)).set({"version": version, "entries": entries})

    wanted = {str(index) for index in range(len(chunks))}
    stale = [ref for ref in catalog.list_documents() if ref.id not in wanted]
    for start in range(0, len(stale), BATCH_LIMIT):
        batch = db.batch()
        for ref in stale[start : start + BATCH_LIMIT]:
            batch.delete(ref)
        batch.commit()

    db.document(META_PATH).set(meta)

    return RebuildResult(
        catalog_version=version,
        chunks=len(chunks),
        poems=len(poems),
        authors_with_poems=len(meta["authors"]),
        themes=len(themes),
    )


def add_poem(db, title: str, text: str, author_id: int, theme_id: int | None) -> int:
    """Create `poems/{nextPoemId}` and advance `meta/content.nextPoemId`; return the new id.

    The catalog is not touched: run `rebuild` afterwards.
    """
    title = title.strip()
    if not title:
        raise ValueError("title must not be empty")
    if not text.strip():
        raise ValueError("text must not be empty")
    meta_ref = db.document(META_PATH)

    @firestore.transactional
    def create(transaction) -> int:
        meta = meta_ref.get(transaction=transaction)
        if not meta.exists:
            raise ValueError("meta/content does not exist yet; run 'migrate' or 'rebuild' first")
        author = db.collection("authors").document(str(author_id)).get(transaction=transaction)
        if not author.exists:
            raise ValueError(f"author {author_id} does not exist")
        if theme_id is not None and not db.collection("themes").document(str(theme_id)).get(
            transaction=transaction
        ).exists:
            raise ValueError(f"theme {theme_id} does not exist")
        poem_id = meta.to_dict()["nextPoemId"]
        poem_ref = db.collection("poems").document(str(poem_id))
        if poem_ref.get(transaction=transaction).exists:
            raise ValueError(
                f"poems/{poem_id} already exists, so nextPoemId is out of date; "
                "run 'rebuild' and try again"
            )
        now = datetime.now(timezone.utc)
        row = PoemRow(
            id=poem_id,
            title=title,
            text=text,
            author_id=author_id,
            theme_id=theme_id,
            created_at=now,
            updated_at=now,
        )
        transaction.set(poem_ref, poem_document(row, author.to_dict()["name"]))
        transaction.update(meta_ref, {"nextPoemId": poem_id + 1})
        return poem_id

    return create(db.transaction())
