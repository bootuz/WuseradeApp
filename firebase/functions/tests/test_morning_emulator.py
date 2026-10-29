"""send_due against the emulator (project demo-wuserade), with a fake sender."""

from datetime import datetime, timezone
from types import SimpleNamespace

from firebase_admin import messaging

from wuserade_daily.morning import next_send_at, send_due

UTC = timezone.utc
NOW = datetime(2026, 10, 29, 5, 0, tzinfo=UTC)


class FakeSend:
    """Stands in for messaging.send_each; `failures` maps a token to the exception it fails with."""

    def __init__(self, failures=None):
        self.failures = failures or {}
        self.sent = []

    def __call__(self, messages):
        self.sent.extend(messages)
        responses = []
        for m in messages:
            error = self.failures.get(m.token)
            responses.append(SimpleNamespace(success=error is None, exception=error))
        return SimpleNamespace(responses=responses)


def seed_daily(db, date, title="Poem"):
    db.document(f"daily/{date}").set(
        {"date": date, "poem": {"id": 1, "title": title, "authorId": 1, "authorName": "A", "text": "a\nb\nc"}}
    )


def seed_device(db, uid, install, token, tz="Europe/Moscow", notify="08:00", due=NOW, enabled=True):
    ref = db.document(f"users/{uid}/devices/{install}")
    ref.set(
        {"fcmToken": token, "timeZone": tz, "notifyAt": notify, "enabled": enabled, "nextSendAt": due, "updatedAt": due}
    )
    return ref


def test_send_due_sends_once_and_advances(db):
    seed_daily(db, "2026-10-29")
    due = seed_device(db, "u1", "i1", "t1")
    seed_device(db, "u2", "i2", "t2", enabled=False)
    seed_device(db, "u3", "i3", "t3", due=datetime(2026, 10, 29, 5, 1, tzinfo=UTC))
    send = FakeSend()
    assert send_due(db, NOW, send) == 1
    assert [m.token for m in send.sent] == ["t1"]
    assert due.get().get("nextSendAt") == next_send_at("Europe/Moscow", "08:00", NOW)
    assert send_due(db, NOW, send) == 0
    assert len(send.sent) == 1


def test_send_due_deletes_unregistered_tokens(db):
    seed_daily(db, "2026-10-29")
    gone = seed_device(db, "u1", "i1", "gone")
    mismatch = seed_device(db, "u2", "i2", "mismatch")
    flaky = seed_device(db, "u3", "i3", "flaky")
    ok = seed_device(db, "u4", "i4", "ok")
    send = FakeSend(
        {
            "gone": messaging.UnregisteredError("x"),
            "mismatch": messaging.SenderIdMismatchError("x"),
            "flaky": messaging.QuotaExceededError("x"),
        }
    )
    assert send_due(db, NOW, send) == 1
    assert not gone.get().exists
    assert not mismatch.get().exists
    assert flaky.get().exists and flaky.get().get("nextSendAt") > NOW
    assert ok.get().get("nextSendAt") > NOW


def test_send_due_uses_the_devices_local_date(db):
    seed_daily(db, "2026-10-29", title="Today")
    seed_daily(db, "2026-10-30", title="Tomorrow")
    now = datetime(2026, 10, 29, 18, 0, tzinfo=UTC)  # 08:00 on the 30th in Kiritimati
    seed_device(db, "u1", "i1", "kiri", tz="Pacific/Kiritimati", due=now)
    seed_device(db, "u2", "i2", "moscow", tz="Europe/Moscow", due=now)
    send = FakeSend()
    assert send_due(db, now, send) == 2
    titles = {m.token: m.notification.title for m in send.sent}
    assert titles["kiri"].startswith("Tomorrow")
    assert titles["moscow"].startswith("Today")


def test_send_due_skips_missing_daily_but_advances(db):
    device = seed_device(db, "u1", "i1", "t1")
    send = FakeSend()
    assert send_due(db, NOW, send) == 0
    assert send.sent == []
    assert device.get().get("nextSendAt") > NOW


def test_send_due_pages_over_500(db):
    seed_daily(db, "2026-10-29")
    for start in range(0, 520, 250):
        batch = db.batch()
        for n in range(start, min(start + 250, 520)):
            batch.set(
                db.document(f"users/u{n}/devices/i"),
                {
                    "fcmToken": f"t{n}",
                    "timeZone": "Europe/Moscow",
                    "notifyAt": "08:00",
                    "enabled": True,
                    "nextSendAt": NOW,
                    "updatedAt": NOW,
                },
            )
        batch.commit()
    send = FakeSend()
    assert send_due(db, NOW, send) == 520
    assert len({m.token for m in send.sent}) == 520
