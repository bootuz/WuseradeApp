"""Cloud Functions entry point (europe-west3)."""

from datetime import datetime, timezone

import firebase_admin
from firebase_admin import firestore, messaging
from firebase_functions import https_fn, scheduler_fn

from wuserade_daily.daily import write_missing_days
from wuserade_daily.handler import handle_keep_reading
from wuserade_daily.keep_reading import CatalogCache
from wuserade_daily.morning import send_due

firebase_admin.initialize_app()


@scheduler_fn.on_schedule(schedule="10 0 * * *", timezone="UTC", region="europe-west3")
def writeDailyPicks(event: scheduler_fn.ScheduledEvent) -> None:
    """Write the daily documents from yesterday to a week ahead that don't exist yet."""
    written = write_missing_days(firestore.client(), datetime.now(timezone.utc).date())
    print(f"daily documents written: {written}")


@scheduler_fn.on_schedule(schedule="*/15 * * * *", region="europe-west3", max_instances=1, timeout_sec=540)
def sendMorningPoems(event: scheduler_fn.ScheduledEvent) -> None:
    """Send the day's poem to every device whose morning time has come."""
    sent = send_due(firestore.client(), datetime.now(timezone.utc), messaging.send_each)
    print(f"morning poems sent: {sent}")


_catalog_cache =CatalogCache()


@https_fn.on_call(region="europe-west3")
def keepReading(req: https_fn.CallableRequest) -> dict:
    """More by the poem's poet and similar poems, leaving out what the caller has read."""
    return handle_keep_reading(req, firestore.client(), _catalog_cache)
