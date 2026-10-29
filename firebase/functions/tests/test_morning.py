"""Pure tests of the morning push schedule and message."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from wuserade_daily import morning
from wuserade_daily.morning import message, next_send_at, send_due

UTC = timezone.utc


def test_next_send_at_same_day_and_next_day():
    after = datetime(2026, 10, 29, 4, 0, tzinfo=UTC)  # 07:00 in Moscow
    assert next_send_at("Europe/Moscow", "08:00", after) == datetime(2026, 10, 29, 5, 0, tzinfo=UTC)
    at = datetime(2026, 10, 29, 5, 0, tzinfo=UTC)
    assert next_send_at("Europe/Moscow", "08:00", at) == datetime(2026, 10, 30, 5, 0, tzinfo=UTC)


def test_next_send_at_skipped_hour_moves_forward():
    after = datetime(2027, 3, 27, 12, 0, tzinfo=UTC)
    assert next_send_at("Europe/Berlin", "02:30", after) == datetime(2027, 3, 28, 1, 30, tzinfo=UTC)


def test_next_send_at_repeated_hour_uses_first():
    after = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
    assert next_send_at("Europe/Berlin", "02:30", after) == datetime(2026, 10, 25, 0, 30, tzinfo=UTC)


def test_next_send_at_far_zones():
    after = datetime(2026, 10, 29, 12, 0, tzinfo=UTC)
    # Kiritimati is UTC+14, Pago Pago UTC-11.
    assert next_send_at("Pacific/Kiritimati", "08:00", after) == datetime(2026, 10, 29, 18, 0, tzinfo=UTC)
    assert next_send_at("Pacific/Pago_Pago", "08:00", after) == datetime(2026, 10, 29, 19, 0, tzinfo=UTC)


def test_next_send_at_is_strictly_after_and_utc():
    result = next_send_at("Asia/Kolkata", "08:00", datetime(2026, 10, 29, 2, 30, tzinfo=UTC))
    assert result == datetime(2026, 10, 30, 2, 30, tzinfo=UTC)
    assert result.utcoffset().total_seconds() == 0


def _daily(**poem):
    base = {"id": 7, "title": "ПСЫ ЦӀЫКӀУ", "authorName": "А", "text": "Line one,\nLine two\nLine three"}
    return {"date": "2026-10-29", "poem": {**base, **poem}}


def test_titled_message():
    m = message("tok", _daily())
    assert m.token == "tok"
    assert m.notification.title == "Псы цӀыкӀу — А"
    assert m.notification.body == "Line one,\nLine two"
    assert m.data == {"poemId": "7", "date": "2026-10-29"}
    assert m.apns.payload.aps.sound is None


def test_untitled_message_uses_first_line():
    m = message("t", _daily(title=""))
    assert m.notification.title == "Line one — А"
    assert m.notification.body == "Line one,\nLine two"


def test_body_and_untitled_headline_use_the_one_palochka():
    # U+04CF and a Latin I beside Cyrillic letters are both spellings of the palochka (U+04C0).
    m = message("t", _daily(title="", text="аӏб,\nвIг\nдеж"))
    assert m.notification.title == "аӀб — А"
    assert m.notification.body == "аӀб,\nвӀг"


# One push per token per run. A fake Firestore client: the due query returns `devices` in order, a page at
# a time; every batch commit is recorded.

NOW = datetime(2026, 10, 29, 5, 0, tzinfo=UTC)


class _Ref:
    def __init__(self, path, db):
        self.path, self._db = path, db

    def get(self):
        data = self._db.docs.get(self.path)
        return SimpleNamespace(exists=data is not None, to_dict=lambda: data)


class _Device:
    def __init__(self, uid, token, updated, db):
        self.reference = _Ref(f"users/{uid}/devices/i", db)
        self._data = {
            "fcmToken": token,
            "timeZone": "Europe/Moscow",
            "notifyAt": "08:00",
            "enabled": True,
            "nextSendAt": NOW,
            "updatedAt": updated,
        }

    def to_dict(self):
        return dict(self._data)


class _Query:
    def __init__(self, db, start=0, size=None):
        self._db, self._start, self._size = db, start, size

    def where(self, filter=None):
        return self

    def order_by(self, *args, **kwargs):
        return self

    def limit(self, size):
        return _Query(self._db, self._start, size)

    def start_after(self, cursor):
        return _Query(self._db, self._db.devices.index(cursor) + 1, self._size)

    def stream(self):
        return iter(self._db.devices[self._start : self._start + self._size])


class _Batch:
    def __init__(self, db):
        self._db, self._ops = db, []

    def update(self, ref, fields):
        self._ops.append(("update", ref.path))

    def delete(self, ref):
        self._ops.append(("delete", ref.path))

    def commit(self):
        self._db.commits.append(self._ops)


class _Db:
    def __init__(self):
        self.docs = {
            "daily/2026-10-29": {
                "date": "2026-10-29",
                "poem": {"id": 1, "title": "Poem", "authorName": "A", "text": "a\nb"},
            }
        }
        self.devices, self.commits = [], []

    def device(self, uid, token, minutes=0):
        device = _Device(uid, token, NOW - timedelta(days=1) + timedelta(minutes=minutes), self)
        self.devices.append(device)
        return device

    def collection_group(self, name):
        return _Query(self)

    def document(self, path):
        return _Ref(path, self)

    def batch(self):
        return _Batch(self)

    def deleted(self):
        return [path for ops in self.commits for op, path in ops if op == "delete"]

    def updated(self):
        return [path for ops in self.commits for op, path in ops if op == "update"]


class _Send:
    def __init__(self):
        self.sent = []

    def __call__(self, messages):
        self.sent.extend(messages)
        return SimpleNamespace(responses=[SimpleNamespace(success=True, exception=None) for _ in messages])


def test_devices_sharing_a_token_get_one_push_and_the_others_are_deleted():
    db, send = _Db(), _Send()
    db.device("old", "shared", minutes=0)
    db.device("new", "shared", minutes=5)
    db.device("other", "own")

    assert send_due(db, NOW, send) == 2
    assert sorted(m.token for m in send.sent) == ["own", "shared"]
    assert db.deleted() == ["users/old/devices/i"]
    # The delete goes in the same commit that advances the devices, before anything is sent.
    assert ("delete", "users/old/devices/i") in db.commits[0]
    assert "users/old/devices/i" not in db.updated()


def test_the_newest_updated_at_wins_whatever_the_order():
    db, send = _Db(), _Send()
    db.device("newest", "shared", minutes=30)
    db.device("middle", "shared", minutes=10)
    db.device("oldest", "shared", minutes=0)

    assert send_due(db, NOW, send) == 1
    assert sorted(db.deleted()) == ["users/middle/devices/i", "users/oldest/devices/i"]
    assert db.updated() == ["users/newest/devices/i"]


def test_a_shared_token_on_a_later_page_is_not_sent_again(monkeypatch):
    monkeypatch.setattr(morning, "PAGE_SIZE", 2)
    db, send = _Db(), _Send()
    db.device("a", "shared", minutes=0)
    db.device("b", "own-b")
    db.device("c", "own-c")
    db.device("d", "shared", minutes=5)  # second page, newer

    assert send_due(db, NOW, send) == 3
    assert sorted(m.token for m in send.sent) == ["own-b", "own-c", "shared"]
    # The newer device is kept and advanced; the one the push went to earlier in the run is deleted.
    assert db.deleted() == ["users/a/devices/i"]
    assert "users/d/devices/i" in db.updated()


def test_an_older_shared_token_on_a_later_page_is_deleted(monkeypatch):
    monkeypatch.setattr(morning, "PAGE_SIZE", 2)
    db, send = _Db(), _Send()
    db.device("a", "shared", minutes=5)
    db.device("b", "own-b")
    db.device("c", "shared", minutes=0)  # second page, older

    assert send_due(db, NOW, send) == 2
    assert [m.token for m in send.sent].count("shared") == 1
    assert db.deleted() == ["users/c/devices/i"]
