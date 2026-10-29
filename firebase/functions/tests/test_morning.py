"""Pure tests of the morning push schedule and message."""

from datetime import datetime, timezone

from wuserade_daily.morning import message, next_send_at

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
