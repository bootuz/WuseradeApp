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
