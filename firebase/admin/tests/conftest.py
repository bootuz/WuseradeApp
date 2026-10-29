"""Shared fixtures for the emulator tests.

Emulator tests skip (never fail) when the emulator they need is not running: Firestore for
`db`, Storage for `storage_bucket`, Auth for `auth_emulator`. Run them with
`firebase emulators:exec --only firestore,storage,auth`, see README.md. They only ever talk
to project demo-wuserade.
"""

import os
import urllib.request

import firebase_admin
import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud import storage

from wuserade_admin import photos, store


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


@pytest.fixture
def storage_bucket():
    """The Storage emulator's bucket for demo-wuserade, emptied before the test."""
    host = photos.storage_emulator_host()
    if not host:
        pytest.skip("no Storage emulator (run through firebase emulators:exec --only firestore,storage,auth)")
    client = storage.Client(
        project=store.EMULATOR_PROJECT_ID,
        credentials=AnonymousCredentials(),
        client_options={"api_endpoint": host},
    )
    bucket = client.bucket(photos.EMULATOR_BUCKET)
    for blob in list(client.list_blobs(bucket)):
        blob.delete()
    yield bucket
    client.close()


@pytest.fixture
def auth_emulator():
    """The Auth emulator's host, with every account deleted."""
    host = os.environ.get("FIREBASE_AUTH_EMULATOR_HOST")
    if not host:
        pytest.skip("FIREBASE_AUTH_EMULATOR_HOST is not set (run through firebase emulators:exec)")
    url = f"http://{host}/emulator/v1/projects/{store.EMULATOR_PROJECT_ID}/accounts"
    with urllib.request.urlopen(urllib.request.Request(url, method="DELETE")) as response:
        response.read()
    return host


@pytest.fixture
def services(db, storage_bucket, auth_emulator):
    """The Firestore, Storage and Auth emulators together, as `photos.connect()` builds them."""
    connected = photos.connect()
    yield connected
    connected.db.close()
    connected.bucket.client.close()
    # photos.connect() leaves a default firebase_admin app behind; later tests start without one.
    try:
        firebase_admin.delete_app(firebase_admin.get_app())
    except ValueError:
        pass
