"""Reader photos of poets: list, approve, reject and remove them, and block senders (Firebase Admin SDK).

A reader's photo waits in Storage at `photo-submissions/{authorId}/{uid}.jpg`, with a record
`photoSubmissions/{authorId}_{uid}`. Approving publishes it at `poets/{authorId}.jpg` and sets
`photoURL` on `authors/{id}` and on the poet's entry in `meta/content.authors`, in one
transaction and without a rebuild, so apps do not download the catalog again. Blocking a sender
sets the `photoBan` claim on their account, which both rule sets check.

Security rules do not apply to the Admin SDK. With the Firestore, Storage and Auth emulators
all set, everything goes to them (project `demo-wuserade`) and nothing else. With none set it goes
to project `wuserade`. Anything in between is refused, because the part without an emulator would
reach the real project, or the part with one would get data meant for the real project.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import datetime
from io import BytesIO
from pathlib import Path
from urllib.parse import quote
from uuid import uuid4

import firebase_admin
from firebase_admin import auth, firestore
from firebase_admin import storage as firebase_storage
from google.api_core.exceptions import FailedPrecondition, NotFound
from google.auth.credentials import AnonymousCredentials
from google.cloud import storage
from google.cloud.firestore_v1.base_query import FieldFilter
from PIL import Image, ImageOps

from . import store

BUCKET = "wuserade.firebasestorage.app"
EMULATOR_BUCKET = "demo-wuserade.appspot.com"
PUBLIC_HOST = "https://firebasestorage.googleapis.com"

SUBMISSIONS = "photoSubmissions"
SUBMISSIONS_PREFIX = "photo-submissions/"

# A year: the URL of a replaced photo changes (see `approve`), so a cached copy never goes stale.
CACHE_CONTROL = "public, max-age=31536000"

BAN_CLAIM = "photoBan"
UNKNOWN_POET = "(unknown poet)"

_SUBMISSION_ID = re.compile(r"([0-9]+)_([^_/\s]+)")
_NOT_IN_A_FILE_NAME = re.compile(r"[/\\:]")
_SUBMISSION_FILE = re.compile(re.escape(SUBMISSIONS_PREFIX) + r"([0-9]+)/([^_/\s]+)\.jpg")


@dataclass(frozen=True)
class PhotoServices:
    db: firestore.Client
    bucket: storage.Bucket
    download_host: str  # PUBLIC_HOST, or the Storage emulator's http://host:port


@dataclass(frozen=True)
class Submission:
    """A waiting photo, as `list_submissions` found it."""

    id: str  # "{authorId}_{uid}"
    author_id: int
    uid: str
    poet_name: str
    created_at: datetime  # when the record was made; for a file without a record, when the file was
    path: Path | None  # the downloaded copy; None when the submission has a record but no photo file


def storage_emulator_host() -> str | None:
    """The Storage emulator as http://host:port, or None when there is none."""
    host = os.environ.get("STORAGE_EMULATOR_HOST")
    if host:
        return host if "://" in host else f"http://{host}"
    host = os.environ.get("FIREBASE_STORAGE_EMULATOR_HOST")
    return f"http://{host}" if host else None


def connect() -> PhotoServices:
    """Firestore and Storage: the emulators if all three emulators are set, else project `wuserade`.

    "Set" means FIRESTORE_EMULATOR_HOST, FIREBASE_AUTH_EMULATOR_HOST, and STORAGE_EMULATOR_HOST or
    FIREBASE_STORAGE_EMULATOR_HOST. Some but not all of them is a ValueError, raised before any
    client is built. Under the emulators a default firebase_admin app (project `demo-wuserade`) is
    made as well, so that `firebase_admin.auth` talks to the Auth emulator.
    """
    storage_host = storage_emulator_host()
    hosts = {
        "Firestore": os.environ.get("FIRESTORE_EMULATOR_HOST"),
        "Storage": storage_host,
        "Auth": os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"),
    }
    unset = [name for name, host in hosts.items() if not host]
    if 0 < len(unset) < len(hosts):
        raise ValueError(
            f"the {' and '.join(unset)} emulator is not set, but another one is; "
            "run through emulators:exec --only firestore,storage,auth, "
            "or unset every emulator variable to use project wuserade"
        )
    if unset:
        db = store.connect()  # also creates the default firebase_admin app
        return PhotoServices(db=db, bucket=firebase_storage.bucket(BUCKET), download_host=PUBLIC_HOST)

    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(options={"projectId": store.EMULATOR_PROJECT_ID})
    client = storage.Client(
        project=store.EMULATOR_PROJECT_ID,
        credentials=AnonymousCredentials(),
        client_options={"api_endpoint": storage_host},
    )
    return PhotoServices(db=store.connect(), bucket=client.bucket(EMULATOR_BUCKET), download_host=storage_host)


def parse_submission_id(submission_id: str) -> tuple[int, str]:
    """"12_uid" -> (12, "uid"); ValueError for anything else."""
    match = _SUBMISSION_ID.fullmatch(submission_id)
    if not match:
        raise ValueError(f"{submission_id!r} is not a submission id; it looks like 12_uid (poet id, underscore, uid)")
    return int(match[1]), match[2]


def sender_uid(uid_or_submission_id: str) -> str:
    """The sender's uid, from a uid or from a submission id like "12_uid". Firebase uids contain no "_"."""
    if "_" in uid_or_submission_id:
        return parse_submission_id(uid_or_submission_id)[1]
    if not uid_or_submission_id.strip():
        raise ValueError("give a uid or a submission id like 12_uid")
    return uid_or_submission_id


def submission_path(author_id: int, uid: str) -> str:
    return f"{SUBMISSIONS_PREFIX}{author_id}/{uid}.jpg"


def poet_path(author_id: int) -> str:
    return f"poets/{author_id}.jpg"


def _on_white(image: Image.Image) -> Image.Image:
    """`image` as RGB; transparent parts become white, not whatever colour is stored under them."""
    if "A" not in image.getbands() and "transparency" not in image.info:
        return image.convert("RGB")
    rgba = image.convert("RGBA")
    flat = Image.new("RGB", rgba.size, (255, 255, 255))
    flat.paste(rgba, mask=rgba.getchannel("A"))
    return flat


def publishable_jpeg(data: bytes, max_side: int = 1024) -> bytes:
    """`data` as an RGB JPEG whose long side is at most `max_side`, turned upright, without metadata.

    A smaller photo keeps its size. Nothing that came with the file survives except its colour
    profile: EXIF, XMP and JPEG comments can all hold the place where the photo was taken, and
    Pillow writes some of them back on save unless they are cleared. A colour profile is kept only
    when it is an RGB one, because the result is RGB.
    """
    try:
        source = ImageOps.exif_transpose(Image.open(BytesIO(data)))
        icc_profile = source.info.get("icc_profile") if source.mode in ("RGB", "RGBA") else None
        image = _on_white(source)
    except (OSError, SyntaxError, ValueError, Image.DecompressionBombError) as error:
        raise ValueError("the photo is not an image that can be read") from error
    image.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    image.info.clear()
    out = BytesIO()
    image.save(out, "JPEG", quality=85, icc_profile=icc_profile)
    return out.getvalue()


def download_url(host: str, bucket: str, path: str, token: str) -> str:
    """The public URL of an object, which carries its download token."""
    return f"{host}/v0/b/{bucket}/o/{quote(path, safe='')}?alt=media&token={token}"


def _delete_blob(blob) -> bool:
    """Delete `blob`; False when it was already gone."""
    try:
        blob.delete()
    except NotFound:
        return False
    return True


def delete_submissions(services: PhotoServices, *, author_id: int | None = None, uid: str | None = None) -> int:
    """Delete waiting photos, their records and their files; return how many submissions that was.

    Give exactly one of: `author_id`, for every submission to that poet, or `uid`, for every
    submission from that sender. Records are found by query and files by listing, so a file whose
    record was never written (the upload comes first) is deleted too. A submission with both a
    record and a file counts once.
    """
    if (author_id is None) == (uid is None):
        raise ValueError("give author_id or uid, not both and not neither")

    submissions = services.db.collection(SUBMISSIONS)
    if author_id is not None:
        records = submissions.where(filter=FieldFilter("authorId", "==", author_id))
        blobs = services.bucket.list_blobs(prefix=f"{SUBMISSIONS_PREFIX}{author_id}/")
    else:
        records = submissions.where(filter=FieldFilter("submittedBy", "==", uid))
        # Files cannot be listed by their last part: list them all and keep the sender's.
        blobs = (b for b in services.bucket.list_blobs(prefix=SUBMISSIONS_PREFIX) if b.name.endswith(f"/{uid}.jpg"))

    removed: set[str] = set()
    refs = []
    for snapshot in records.stream():
        refs.append(snapshot.reference)
        removed.add(snapshot.id)
    for start in range(0, len(refs), store.BATCH_LIMIT):
        batch = services.db.batch()
        for ref in refs[start : start + store.BATCH_LIMIT]:
            batch.delete(ref)
        batch.commit()

    for blob in list(blobs):
        if _delete_blob(blob):
            folder, _, file = blob.name.removeprefix(SUBMISSIONS_PREFIX).partition("/")
            removed.add(f"{folder}_{file.removesuffix('.jpg')}")
    return len(removed)


def _poet_entry_index(author, meta: dict | None, author_id: int, *, listed: bool) -> int | None:
    """Where the poet is in `meta.authors`; ValueError when `authors/{id}` is missing.

    With `listed=True` the poet must also have an entry (only poets with poems do), else ValueError.
    """
    if not author.exists:
        raise ValueError(f"authors/{author_id} does not exist")
    for index, entry in enumerate((meta or {}).get("authors", [])):
        if entry.get("id") == author_id:
            return index
    if listed:
        raise ValueError(
            f"poet {author_id} is not in meta/content.authors (only poets with poems are); "
            "add poems and run 'rebuild' first"
        )
    return None


def _set_photo_url(db, author_id: int, url: str | None) -> None:
    """Set `photoURL` on authors/{id} and on the poet's meta/content entry, or clear both with None.

    One transaction. Nothing else in meta changes, so the catalog version stays.
    """
    author_ref = db.collection("authors").document(str(author_id))
    meta_ref = db.document(store.META_PATH)

    @firestore.transactional
    def write(transaction) -> None:
        author = author_ref.get(transaction=transaction)
        meta = meta_ref.get(transaction=transaction).to_dict()
        # Taking a photo down works for a poet who has since left the list; putting one up does not.
        index = _poet_entry_index(author, meta, author_id, listed=url is not None)
        transaction.update(author_ref, {"photoURL": url})
        if index is not None:
            authors = list(meta["authors"])
            entry = {key: value for key, value in authors[index].items() if key != "photoURL"}
            authors[index] = {**entry, "photoURL": url} if url is not None else entry
            transaction.update(meta_ref, {"authors": authors})

    write(db.transaction())


def approve(services: PhotoServices, submission_id: str, file: Path | None = None) -> str:
    """Publish a waiting photo as the poet's photo; return its new `photoURL`.

    The photo is the submission's file, or `file` (the owner's cropped copy), resized to at most
    1024 px. It replaces any earlier photo of the poet, and then every waiting submission for the
    poet is deleted. Everything is checked before the first write.

    The download token is new on every approval, so a replaced photo gets a new URL and devices
    that cached the old one show the new one.
    """
    author_id, uid = parse_submission_id(submission_id)
    db = services.db
    if not db.collection(SUBMISSIONS).document(submission_id).get().exists:
        raise ValueError(f"no waiting photo {submission_id}")
    _poet_entry_index(
        db.collection("authors").document(str(author_id)).get(),
        db.document(store.META_PATH).get().to_dict(),
        author_id,
        listed=True,
    )
    if file is not None:
        try:
            data = file.read_bytes()
        except OSError as error:
            raise ValueError(f"cannot read {file}: {error.strerror}") from error
    else:
        try:
            data = services.bucket.blob(submission_path(author_id, uid)).download_as_bytes()
        except NotFound:
            raise ValueError(
                f"{submission_id} has no photo file; reject it, or approve it with --file"
            ) from None
    jpeg = publishable_jpeg(data)

    token = uuid4().hex
    blob = services.bucket.blob(poet_path(author_id))
    blob.metadata = {"firebaseStorageDownloadTokens": token}
    blob.cache_control = CACHE_CONTROL
    blob.upload_from_string(jpeg, content_type="image/jpeg")
    url = download_url(services.download_host, services.bucket.name, blob.name, token)

    _set_photo_url(db, author_id, url)
    delete_submissions(services, author_id=author_id)
    return url


def reject(services: PhotoServices, submission_id: str) -> None:
    """Delete one waiting photo: its record and its file, whichever of the two exist."""
    author_id, uid = parse_submission_id(submission_id)
    record = services.db.collection(SUBMISSIONS).document(submission_id)
    try:
        record.delete(option=services.db.write_option(exists=True))
        had_record = True
    except (NotFound, FailedPrecondition):  # the emulator answers the first, production may answer either
        had_record = False
    had_file = _delete_blob(services.bucket.blob(submission_path(author_id, uid)))
    if not had_record and not had_file:
        raise ValueError(f"no waiting photo {submission_id}")


def remove(services: PhotoServices, author_id: int) -> None:
    """Take the poet's approved photo down: clear `photoURL` in both places, then delete the file."""
    _set_photo_url(services.db, author_id, None)
    _delete_blob(services.bucket.blob(poet_path(author_id)))


def _poet_names(db, author_ids: set[int]) -> dict[int, str]:
    """The name in `authors/{id}` for each poet that has the document."""
    refs = [db.collection("authors").document(str(author_id)) for author_id in sorted(author_ids)]
    if not refs:
        return {}
    return {
        int(snapshot.id): snapshot.to_dict().get("name") or UNKNOWN_POET
        for snapshot in db.get_all(refs)
        if snapshot.exists
    }


def _file_name(author_id: int, poet_name: str, uid: str) -> str:
    """The name of a downloaded photo: poet id, poet name and the first six characters of the uid."""
    return f"{author_id}-{_NOT_IN_A_FILE_NAME.sub('-', poet_name)}-{uid[:6]}.jpg"


def list_submissions(services: PhotoServices, out_dir: Path) -> list[Submission]:
    """Download every waiting photo into `out_dir` (made if needed); return them, oldest first.

    Records and files are both looked at, so nothing waiting is hidden: a file whose record was
    never written is listed with its id taken from its path and its age from the file, and a record
    whose file is gone is listed with `path=None`.

    The records are read before the files. A sender's app uploads the file and then writes the
    record, so a submission that lands between the two reads shows up as a file without a record
    (still listed, with its photo) and never as a record without its file.
    """
    snapshots = list(services.db.collection(SUBMISSIONS).stream())
    files = {blob.name: blob for blob in services.bucket.list_blobs(prefix=SUBMISSIONS_PREFIX)}
    rows = []  # (id, author_id, uid, created_at, file); file is None when there is no photo file
    for snapshot in snapshots:
        record = snapshot.to_dict()
        author_id, uid = record["authorId"], record["submittedBy"]
        file = files.pop(submission_path(author_id, uid), None)
        rows.append((snapshot.id, author_id, uid, record["createdAt"], file))
    for name, blob in files.items():
        match = _SUBMISSION_FILE.fullmatch(name)
        if match:
            rows.append((f"{match[1]}_{match[2]}", int(match[1]), match[2], blob.time_created, blob))
    rows.sort(key=lambda row: (row[3], row[0]))

    names = _poet_names(services.db, {row[1] for row in rows})
    out_dir.mkdir(parents=True, exist_ok=True)
    submissions = []
    for submission_id, author_id, uid, created_at, file in rows:
        poet_name = names.get(author_id, UNKNOWN_POET)
        path = None
        if file is not None:
            path = out_dir / _file_name(author_id, poet_name, uid)
            try:
                file.download_to_filename(path)
            except NotFound:  # deleted since it was listed
                path = None
        submissions.append(Submission(submission_id, author_id, uid, poet_name, created_at, path))
    return submissions


def _claims(uid: str) -> dict:
    """The custom claims on the account `uid`; ValueError when there is no such account."""
    try:
        return auth.get_user(uid).custom_claims or {}
    except auth.UserNotFoundError:
        raise ValueError(f"no account with uid {uid}") from None


def ban(services: PhotoServices, uid_or_submission_id: str) -> int:
    """Stop a sender from sending photos; return how many of their waiting photos were deleted.

    Sets the `photoBan` claim next to the account's other claims, revokes its refresh tokens, and
    then deletes their waiting submissions. An unknown account changes nothing.

    The rules read the claim from the ID token the sender sends, and revoking does not cancel an
    ID token that was already issued. So the ban applies from the sender's next token refresh;
    until then, within the hour, a token they hold keeps working.
    """
    uid = sender_uid(uid_or_submission_id)
    auth.set_custom_user_claims(uid, {**_claims(uid), BAN_CLAIM: True})
    auth.revoke_refresh_tokens(uid)
    return delete_submissions(services, uid=uid)


def unban(services: PhotoServices, uid: str) -> None:
    """Let a sender send photos again: remove the `photoBan` claim and keep their other claims.

    `services` is not used (the Auth client is the default app's); it is here so that `ban` and
    `unban` are called the same way.
    """
    claims = _claims(uid)
    claims.pop(BAN_CLAIM, None)
    auth.set_custom_user_claims(uid, claims or None)  # None clears the claims
