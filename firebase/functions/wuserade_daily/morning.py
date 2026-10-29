"""The morning push: when a device is next due, what the notification says, and sending it."""

from __future__ import annotations

import logging
import warnings
from datetime import date, datetime, time, timedelta, timezone
from typing import TYPE_CHECKING, Callable
from zoneinfo import ZoneInfo

from firebase_admin import messaging
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from wuserade_daily.text import first_lines, sentence_case

if TYPE_CHECKING:
    from google.cloud.firestore import Client

log = logging.getLogger(__name__)

PAGE_SIZE = 500
# Trimmed from the end of an untitled poem's first line, as the app's PoemSummary.firstLine does.
_TRAILING = ",.;:!?—– "


def next_send_at(time_zone: str, notify_at: str, after: datetime) -> datetime:
    """The first UTC instant strictly after `after` at which `time_zone`'s clock reads `notify_at`.

    A local time skipped by a daylight-saving change moves forward by the gap (02:30 becomes 03:30).
    A repeated local time uses its first occurrence.
    """
    zone = ZoneInfo(time_zone)
    hour, minute = (int(part) for part in notify_at.split(":"))
    local_day = after.astimezone(zone).date()
    for offset in range(-1, 3):
        day = local_day + timedelta(days=offset)
        # fold=0 picks the first occurrence of a repeated time, and for a skipped time the offset
        # from before the change, which lands the instant the gap's length later on the local clock.
        local = datetime.combine(day, time(hour, minute), tzinfo=zone)
        candidate = local.astimezone(timezone.utc)
        if candidate > after:
            return candidate
    raise ValueError(f"no send time found for {time_zone} {notify_at}")  # pragma: no cover


def message(token: str, daily: dict) -> messaging.Message:
    """The notification for a `daily/{date}` document."""
    poem = daily["poem"]
    lines = first_lines(poem["text"], 2)
    title = (poem.get("title") or "").strip()
    if title:
        headline = sentence_case(title)
    else:
        headline = (lines[0] if lines else "").rstrip(_TRAILING)
    with warnings.catch_warnings():
        # `token` is right for an iOS FCM registration token; the SDK's `fid` is a different ID.
        warnings.filterwarnings("ignore", message="Message.token is deprecated", category=DeprecationWarning)
        return messaging.Message(
            token=token,
            notification=messaging.Notification(
                title=f"{headline} \u2014 {poem['authorName']}", body="\n".join(lines)
            ),
            data={"poemId": str(poem["id"]), "date": daily["date"]},
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps())),
        )


def _is_dead_token(error: Exception | None) -> bool:
    return isinstance(error, (messaging.UnregisteredError, messaging.SenderIdMismatchError))


def send_due(
    db: Client,
    now: datetime,
    send: Callable[[list[messaging.Message]], messaging.BatchResponse],
) -> int:
    """Send the day's poem to every enabled device that is due at `now`; returns how many were sent."""
    daily_cache: dict[str, dict | None] = {}
    sent = 0
    query = (
        db.collection_group("devices")
        .where(filter=FieldFilter("enabled", "==", True))
        .where(filter=FieldFilter("nextSendAt", "<=", now))
        .order_by("nextSendAt")
        .limit(PAGE_SIZE)
    )
    cursor = None
    while True:
        page = list((query.start_after(cursor) if cursor else query).stream())
        if not page:
            break
        cursor = page[-1]
        sent += _send_page(db, page, now, send, daily_cache)
        if len(page) < PAGE_SIZE:
            break
    return sent


def _load_daily(db: Client, day: date, cache: dict[str, dict | None]) -> dict | None:
    key = day.isoformat()
    if key not in cache:
        snapshot = db.document(f"daily/{key}").get()
        cache[key] = snapshot.to_dict() if snapshot.exists else None
    return cache[key]


def _send_page(db, page, now, send, daily_cache) -> int:
    to_send = []  # (device snapshot, message)
    updates = []  # (device snapshot, next send time)
    for device in page:
        data = device.to_dict()
        try:
            token = data["fcmToken"]
            if not isinstance(token, str) or not token:
                raise ValueError("fcmToken must be a non-empty string")
            zone = ZoneInfo(data["timeZone"])
            following = next_send_at(data["timeZone"], data["notifyAt"], now)
            daily = _load_daily(db, now.astimezone(zone).date(), daily_cache)
            built = message(token, daily) if daily is not None else None
        except Exception as error:  # noqa: BLE001 - one malformed device must not stop the run
            log.warning("malformed device %s, retrying in a day: %r", device.reference.path, error)
            updates.append((device, now + timedelta(days=1)))
            continue
        updates.append((device, following))
        if built is None:
            log.warning("no daily document for %s, skipping", device.reference.path)
            continue
        to_send.append((device, built))

    # Advance first: a failed commit sends nothing, and a rerun or overlapping run finds nothing due.
    _commit(db, [(d.reference, {"nextSendAt": t, "updatedAt": firestore.SERVER_TIMESTAMP}) for d, t in updates])
    if not to_send:
        return 0

    sent = 0
    dead = []
    response = send([m for _, m in to_send])
    for (device, _), result in zip(to_send, response.responses):
        if result.success:
            sent += 1
        elif _is_dead_token(result.exception):
            dead.append(device.reference)
        else:
            log.error("send failed for %s: %s", device.reference.path, result.exception)
    _commit(db, [(ref, None) for ref in dead])
    return sent


def _commit(db, writes) -> None:
    """Apply (ref, fields) updates, or deletes where fields is None, in batches."""
    for start in range(0, len(writes), PAGE_SIZE):
        batch = db.batch()
        for ref, fields in writes[start : start + PAGE_SIZE]:
            if fields is None:
                batch.delete(ref)
            else:
                batch.update(ref, fields)
        batch.commit()
