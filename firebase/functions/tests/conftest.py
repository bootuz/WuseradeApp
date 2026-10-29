"""Shared fixtures for the functions tests.

Tests that need Firestore use the `db` fixture. It skips (never fails) when the emulator is not
running, and every test that uses it carries the `emulator` marker, so `pytest -m "not emulator"`
runs the pure tests alone. Run the rest through `firebase emulators:exec --only firestore`, see
the admin README. They only ever talk to project demo-wuserade.
"""

import os
import urllib.request

import firebase_admin
import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud import firestore

EMULATOR_PROJECT_ID = "demo-wuserade"


def pytest_collection_modifyitems(items):
    """Mark every test that uses the `db` fixture `emulator`."""
    for item in items:
        if "db" in getattr(item, "fixturenames", ()):
            item.add_marker(pytest.mark.emulator)


def _clear_emulator(host: str) -> None:
    """Delete every document in the emulator's (default) database."""
    url = f"http://{host}/emulator/v1/projects/{EMULATOR_PROJECT_ID}/databases/(default)/documents"
    with urllib.request.urlopen(urllib.request.Request(url, method="DELETE")) as response:
        response.read()


@pytest.fixture
def db():
    """A Firestore client on the emulator for demo-wuserade, emptied before the test."""
    host = os.environ.get("FIRESTORE_EMULATOR_HOST")
    if not host:
        pytest.skip("FIRESTORE_EMULATOR_HOST is not set (run through firebase emulators:exec)")
    _clear_emulator(host)
    # Code under test may call firebase_admin; give it the emulator's project, not `wuserade`.
    firebase_admin.initialize_app(options={"projectId": EMULATOR_PROJECT_ID})
    client = firestore.Client(project=EMULATOR_PROJECT_ID, credentials=AnonymousCredentials())
    assert client.project == EMULATOR_PROJECT_ID
    yield client
    client.close()
    # Later tests start without a default app.
    try:
        firebase_admin.delete_app(firebase_admin.get_app())
    except ValueError:
        pass
