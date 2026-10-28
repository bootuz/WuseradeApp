"""store.connect() choices that need neither the emulator nor real credentials."""

import firebase_admin
import pytest

from wuserade_admin import store


def test_emulator_host_selects_the_demo_project_without_credentials(monkeypatch):
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "localhost:1")

    client = store.connect()

    assert client.project == "demo-wuserade"
    client.close()


def test_missing_credentials_explain_how_to_log_in(monkeypatch, tmp_path):
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
    # A key path that does not exist makes Application Default Credentials fail before any network call.
    monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", str(tmp_path / "missing.json"))
    try:
        with pytest.raises(ValueError, match="gcloud auth application-default login"):
            store.connect()
    finally:
        try:
            firebase_admin.delete_app(firebase_admin.get_app())
        except ValueError:
            pass
