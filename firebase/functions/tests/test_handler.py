"""The keepReading callable's checks (no Functions runtime, no emulator)."""

from types import SimpleNamespace

import pytest
from firebase_functions import https_fn

import wuserade_daily.handler as handler
from wuserade_daily.catalog import Catalog

CODES = https_fn.FunctionsErrorCode


class Cache:
    def __init__(self, error=None):
        self.error = error

    def get(self, db):
        if self.error:
            raise self.error
        return Catalog(version=1, entries=[], poets=[])


def req(data, auth=True):
    return SimpleNamespace(data=data, auth=SimpleNamespace(uid="u1") if auth else None)


def code_of(r, cache=None):
    with pytest.raises(https_fn.HttpsError) as info:
        handler.handle_keep_reading(r, None, cache or Cache())
    return info.value.code


def test_unauthenticated():
    assert code_of(req({"poemId": 1}, auth=False)) == CODES.UNAUTHENTICATED


@pytest.mark.parametrize("data", [None, {}, {"poemId": "1"}, {"poemId": True}, {"poemId": 1.5}, [1]])
def test_bad_poem_id(data):
    assert code_of(req(data)) == CODES.INVALID_ARGUMENT


def test_unknown_poem_is_invalid_argument():
    assert code_of(req({"poemId": 999})) == CODES.INVALID_ARGUMENT


def test_no_catalog_is_unavailable():
    assert code_of(req({"poemId": 1}), Cache(ValueError("rebuild"))) == CODES.UNAVAILABLE


INT64 = "type.googleapis.com/google.protobuf.Int64Value"


def test_poem_id_wrapped_as_int64_by_the_ios_sdk_is_accepted(monkeypatch):
    # FirebaseFunctions on iOS sends a Swift Int as {"@type": ...Int64Value, "value": "59"}, and the Python SDK
    # passes it on undecoded.
    seen = []
    monkeypatch.setattr(handler, "keep_reading", lambda db, uid, poem_id, catalog: seen.append(poem_id) or {})
    handler.handle_keep_reading(req({"poemId": {"@type": INT64, "value": "59"}}), None, Cache())
    assert seen == [59]


@pytest.mark.parametrize(
    "wrapped",
    [
        {"@type": INT64, "value": "5.5"},
        {"@type": INT64, "value": " 59"},
        {"@type": INT64, "value": "--59"},
        {"@type": INT64, "value": "５９"},
        {"@type": INT64, "value": 59},
        {"@type": INT64},
        {"@type": "type.googleapis.com/google.protobuf.StringValue", "value": "59"},
        {"value": "59"},
    ],
)
def test_other_wrapped_values_are_invalid(wrapped):
    assert code_of(req({"poemId": wrapped})) == CODES.INVALID_ARGUMENT
