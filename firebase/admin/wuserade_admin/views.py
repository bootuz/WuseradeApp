"""The view counts of the old site, copied onto the poems in Firestore.

The old Django site counted reads in `poems_poem.views`. `migrate` copies them together with the
poems while the Postgres database exists. The `views` command is for after that: it reads the counts
from Postgres again, or from a `data.json` dump made with Django's `dumpdata` when Postgres is gone,
writes only `poems/{id}.views`, and then rebuilds the catalog, whose entries carry the counts.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import store

POEM_MODEL = "poems.poem"


def _is_whole_number(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def views_from_json(path: Path) -> dict[int, int]:
    """Poem id to view count, read from a Django `dumpdata` file (a JSON list of records).

    Only `poems.poem` records are read; every other model in the dump is ignored. A poem record
    without a whole-number `views` of 0 or more is an error that names the poem, so a dump made
    before the column existed is not mistaken for counts of zero.
    """
    try:
        records = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error.strerror}") from error
    except UnicodeDecodeError:
        raise ValueError(f"{path} is not valid UTF-8") from None
    except json.JSONDecodeError as error:
        raise ValueError(f"{path} is not valid JSON ({error.msg}, line {error.lineno})") from None
    if not isinstance(records, list):
        raise ValueError(f"{path} must hold a JSON list of records, as 'dumpdata' writes it")

    counts: dict[int, int] = {}
    for record in records:
        if not isinstance(record, dict) or record.get("model") != POEM_MODEL:
            continue
        pk = record.get("pk")
        if not _is_whole_number(pk):
            raise ValueError(f"{path} has a {POEM_MODEL} record whose pk is not a whole number ({pk!r})")
        fields = record.get("fields")
        count = fields.get("views") if isinstance(fields, dict) else None
        if not _is_whole_number(count) or count < 0:
            raise ValueError(f"{path}: poem {pk} has no views count (a whole number, 0 or more)")
        counts[pk] = count
    return counts


def copy_views(db, views: dict[int, int]) -> int:
    """Set `poems/{id}.views` for every poem in `views` that exists in Firestore; return how many.

    Poems that are not in Firestore are skipped, never created, and poems that are not in `views`
    keep the count they have. Only the `views` field is written, in batches of at most 500. The
    catalog is not touched: run `rebuild` afterwards.
    """
    # select([]) fetches only the document names, not the poem texts.
    existing = {snapshot.id for snapshot in db.collection("poems").select([]).stream()}
    writes = [
        (db.collection("poems").document(str(poem_id)), {"views": count})
        for poem_id, count in sorted(views.items())
        if str(poem_id) in existing
    ]
    store._commit(db, writes, update=True)
    return len(writes)
