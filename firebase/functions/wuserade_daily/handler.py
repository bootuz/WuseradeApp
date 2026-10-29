"""The `keepReading` callable's logic, apart from the Functions runtime so tests can call it."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from firebase_functions import https_fn

from wuserade_daily.keep_reading import CatalogCache, PoemNotFound, keep_reading

if TYPE_CHECKING:
    from google.cloud.firestore import Client


_INT64 = "type.googleapis.com/google.protobuf.Int64Value"


def _unwrap_int64(value):
    """The int in the callable protocol's Int64Value wrapper, which the iOS SDK sends for a Swift `Int` and the
    Python SDK does not decode; anything else unchanged."""
    if isinstance(value, dict) and value.get("@type") == _INT64:
        text = value.get("value")
        if isinstance(text, str) and re.fullmatch(r"-?[0-9]+", text):
            return int(text)
    return value


def handle_keep_reading(req, db: Client, cache: CatalogCache) -> dict:
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    poem_id = _unwrap_int64(req.data.get("poemId")) if isinstance(req.data, dict) else None
    if not isinstance(poem_id, int) or isinstance(poem_id, bool):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "poemId must be an integer.")
    try:
        catalog = cache.get(db)
    except ValueError:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.UNAVAILABLE, "The catalog is being updated; try again later."
        ) from None
    try:
        return keep_reading(db, req.auth.uid, poem_id, catalog)
    except PoemNotFound:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "No such poem.") from None
