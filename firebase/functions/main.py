"""Cloud Functions entry point (europe-west3)."""

from datetime import datetime, timezone

import firebase_admin
from firebase_admin import firestore
from firebase_functions import https_fn, scheduler_fn

from wuserade_daily.daily import write_missing_days
from wuserade_daily.keep_reading import CatalogCache, PoemNotFound, keep_reading

firebase_admin.initialize_app()


@scheduler_fn.on_schedule(schedule="10 0 * * *", timezone="UTC", region="europe-west3")
def writeDailyPicks(event: scheduler_fn.ScheduledEvent) -> None:
    """Write the daily documents from yesterday to a week ahead that don't exist yet."""
    written = write_missing_days(firestore.client(), datetime.now(timezone.utc).date())
    print(f"daily documents written: {written}")


_catalog_cache = CatalogCache()


@https_fn.on_call(region="europe-west3")
def keepReading(req: https_fn.CallableRequest) -> dict:
    """More by the poem's poet and similar poems, leaving out what the caller has read."""
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    poem_id = (req.data or {}).get("poemId") if isinstance(req.data, dict) else None
    if not isinstance(poem_id, int) or isinstance(poem_id, bool):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "poemId must be an integer.")
    db = firestore.client()
    try:
        return keep_reading(db, req.auth.uid, poem_id, _catalog_cache.get(db))
    except PoemNotFound:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "No such poem.") from None
