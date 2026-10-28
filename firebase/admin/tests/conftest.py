"""Shared fixtures for the Firestore emulator tests.

Emulator tests skip (never fail) when FIRESTORE_EMULATOR_HOST is not set. Run them with
`firebase emulators:exec`, see README.md. They only ever talk to project demo-wuserade.
"""

import os
import urllib.request

import pytest

from wuserade_admin import store


def emulator_host() -> str | None:
    return os.environ.get("FIRESTORE_EMULATOR_HOST")


def _clear_emulator(host: str) -> None:
    """Delete every document in the emulator's (default) database."""
    url = f"http://{host}/emulator/v1/projects/{store.EMULATOR_PROJECT_ID}/databases/(default)/documents"
    request = urllib.request.Request(url, method="DELETE")
    with urllib.request.urlopen(request) as response:
        response.read()


@pytest.fixture
def db():
    host = emulator_host()
    if not host:
        pytest.skip("FIRESTORE_EMULATOR_HOST is not set (run through firebase emulators:exec)")
    _clear_emulator(host)
    client = store.connect()
    assert client.project == "demo-wuserade"
    yield client
    client.close()
