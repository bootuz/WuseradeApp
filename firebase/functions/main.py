"""Cloud Functions entry point (europe-west3)."""

from datetime import datetime, timezone

import firebase_admin
from firebase_admin import firestore
from firebase_functions import scheduler_fn

from wuserade_daily.daily import write_missing_days

firebase_admin.initialize_app()


@scheduler_fn.on_schedule(schedule="10 0 * * *", timezone="UTC", region="europe-west3")
def writeDailyPicks(event: scheduler_fn.ScheduledEvent) -> None:
    """Write the daily documents from yesterday to a week ahead that don't exist yet."""
    written = write_missing_days(firestore.client(), datetime.now(timezone.utc).date())
    print(f"daily documents written: {written}")
