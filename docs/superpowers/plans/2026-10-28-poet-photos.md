# Poet photos sent by readers: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reader signed in with Apple or Google can send a poet's photo from the poet page. The owner approves it from the Mac, and only then does it show, in a round portrait centred above the poet's name.

**Architecture:** There are three parts.
- **Firebase:** a new `storage.rules` and a `photoSubmissions` Firestore collection. Both check the sign-in provider and a `photoBan` claim.
- **Admin tool:** new `photos` commands. Approving publishes the photo to `poets/{id}.jpg` and writes its download URL into `authors/{id}` and `meta/content` in one transaction.
- **App:** reads the URL from the `meta/content` it already caches. It keeps the reader's waiting state in a new `PhotoSubmissions` observable next to `LikesController`, and gives the poet page a centred `PoetHeader` in place of `DetailHeader`.

**Tech Stack:**
- SwiftUI with an iOS 17 target, PhotosUI and ImageIO.
- Firebase iOS SDK 13.1.1, gaining the `FirebaseStorage` product.
- The Python admin tool: firebase-admin, google-cloud-storage (a firebase-admin dependency), Pillow and pytest.
- The Firestore, Storage and Auth emulators.
- `node:test` with `@firebase/rules-unit-testing`.

**Spec:** `docs/superpowers/specs/2026-10-28-poet-photos-design.md` (approved). Read it with this plan; the plan does not repeat its reasons.

## Global Constraints

- **iOS target:** iOS 17.0 stays. Newer APIs go only behind `if #available`.
- **Swift files:** every new file starts with `// Minimum iOS 17.` and a short `//  ` summary, like the files around it. One type per file (nested types are fine).
- **Dependencies:** no new third-party Swift packages. Add only the `FirebaseStorage` product of the firebase-ios-sdk package that is already there. The admin tool may add `Pillow`.
- **Folders:** photo UI goes in a new `wuserade/Photos/` folder, and photo services go in `wuserade/Services/Photos/` (`Services` already syncs, so its subfolders need no project entries).
- **Kabardian copy:** new strings are `[owner copy: …]` slots in `OwnerCopy`, spelled exactly as in the spec. Never write Kabardian. Any palochka is U+04C0. No emoji or heart symbols in text.
- **Design system:**
  - Colours from `Palette` tokens, Alegreya only through `.serif(_:)`, and spacing from `Space` tokens.
  - Buttons use `.primaryCapsule(fullWidth:)` or `.secondaryCapsule`. Sheets close with `CloseButton` and use `FormSheetSizing` on iPad.
  - No focus rings, and system chrome is left alone.
- **Reads:** the app never lists a collection. It reads documents by known ID.
- **Storage:** bucket `wuserade.firebasestorage.app` (us-central1). Waiting photos go to `photo-submissions/{authorId}/{uid}.jpg` and approved ones to `poets/{authorId}.jpg`.
- **The waiting record:** `photoSubmissions/{authorId}_{uid}` holds exactly `authorId: Int`, `submittedBy: String` and `createdAt: Timestamp`.
- **Production:** nothing is deployed to project `wuserade`, and nothing is committed or pushed, until the owner says so. Tests talk only to the emulators (project `demo-wuserade`).
- **Builds:** run `xcodebuild` without `-derivedDataPath`, so it uses the shared DerivedData. Run `df -h /System/Volumes/Data` before the first build; below 20 GB free, stop and tell the owner.

**Commands used below.** Run each from the folder shown.

- **Swift tests, from the repository root.** `<Class>` is a test class name.
  ```bash
  xcodebuild test -project Wuserade.xcodeproj -scheme Wuserade -destination 'platform=iOS Simulator,id=C33052E2-0E82-4A95-B376-B6E33594C7C9' -only-testing:WuseradeTests/<Class> 2>&1 | tail -n 5
  ```
  A pass ends with `** TEST SUCCEEDED **`, a failure with `** TEST FAILED **`. Leave out `-only-testing` to run every test.
- **Admin tests, from `firebase/`:**
  ```bash
  npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore,storage,auth "cd admin && .venv/bin/python -m pytest -q"
  ```
- **Rules tests, from `firebase/`:**
  ```bash
  npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore,storage "npm --prefix rules-tests test"
  ```

## Review Focus

These five are the inputs a reader or the owner is most likely to hit that no task's main tests cover. Each one has a test in the task named.

1. **Signing in from the sheet changes the account.** Linking keeps the anonymous uid, and an existing Apple or Google account brings a new uid. The page must use the signed-in uid either way, and never show another uid's waiting state. Tested by `testUidForState` and `testBindToAnotherUidForgetsStatuses` in Task 6, together with Task 6's wiring rule.
2. **A double tap on Send, or Send while an upload is running.** The result must be one upload and one record. Tested by `testSecondSendWhileSendingIsIgnored` in Task 6.
3. **Deleting the account when the poet list can't be read or a photo delete fails** (for example on a first launch offline). The account must not be deleted with photos left behind, and a retry must finish the job. Tested by `testDeleteAccountStopsWhenWaitingPhotosCannotBeDeleted` in Task 7.
4. **The picker returns a panorama, a small image, or data ImageIO can't read.** The photo must keep its shape and not be enlarged, and a bad file must give an error, never a crash. Tested by `testPanoramaKeepsItsShape`, `testSmallPhotoIsNotEnlarged` and `testUnreadableDataThrows` in Task 8.
5. **The owner approves a second photo for a poet who already has one.** Devices that cached the first must show the new one. Tested by `test_approve_again_changes_the_url` in Task 3.

---

### Task 1: `migrate` and `rebuild` keep approved photos

**Files:**
- Modify: `firebase/admin/wuserade_admin/catalog.py` (`meta_document`)
- Modify: `firebase/admin/wuserade_admin/store.py` (`_commit`, `upsert_content`)
- Test: `firebase/admin/tests/test_catalog.py`, `firebase/admin/tests/test_store_emulator.py`

**Interfaces:**
- Produces:
  - Each `meta/content.authors[]` entry is `{"id", "name", "poemsCount"}`, plus `"photoURL": str` only when the author has one. Tasks 3 and 5 rely on this shape.
  - `_commit(db, writes, *, update=False, merge=False)`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_catalog.py` (build `PoemRow`s the way the file's other `meta_document` tests do):

```python
def test_meta_document_copies_photo_urls():
    authors = {
        1: AuthorRow(id=1, name="А", bio="", photo="https://p/1.jpg"),
        2: AuthorRow(id=2, name="Б", bio="", photo=None),
        3: AuthorRow(id=3, name="В", bio="", photo=""),
    }
    # one poem each for authors 1, 2 and 3
    meta = meta_document([], authors, poems, catalog_version=1, chunk_count=1, minimum_app_version=None)
    assert meta["authors"] == [
        {"id": 1, "name": "А", "poemsCount": 1, "photoURL": "https://p/1.jpg"},
        {"id": 2, "name": "Б", "poemsCount": 1},
        {"id": 3, "name": "В", "poemsCount": 1},
    ]
```

In `tests/test_store_emulator.py`:

```python
def test_upsert_keeps_an_approved_photo(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    db.document("authors/1").update({"photoURL": "https://p/1.jpg"})
    store.upsert_content(db, themes, authors, poems)  # Django's photo is blank
    assert doc(db, "authors/1").to_dict()["photoURL"] == "https://p/1.jpg"

def test_rebuild_keeps_photos_in_meta(db):
    themes, authors, poems = make_content(3)
    store.upsert_content(db, themes, authors, poems)
    db.document("authors/1").update({"photoURL": "https://p/1.jpg"})
    store.rebuild(db)
    entries = {a["id"]: a for a in meta(db)["authors"]}
    assert entries[1]["photoURL"] == "https://p/1.jpg"
    assert "photoURL" not in entries[2]
```

At line 116 of `tests/test_store_emulator.py`, change `to_dict()["photoURL"] is None` to `to_dict().get("photoURL") is None`, because a new author now gets no `photoURL` field.

- [ ] **Step 2: Run the tests to make sure they fail**

Run the admin tests. Expected: `test_meta_document_copies_photo_urls` and `test_upsert_keeps_an_approved_photo` fail, and so does `test_rebuild_keeps_photos_in_meta`, because `photoURL` is missing from the meta entry.

- [ ] **Step 3: Implement**
  - **`meta_document`:** add `"photoURL": a.photo` to an entry only when `a.photo` is truthy.
  - **`_commit`:** with `merge=True`, write `batch.set(ref, data, merge=True)`.
  - **`upsert_content`:** write author documents with `merge=True` and without the `photoURL` key when Django's value is blank. That way a stored URL is never overwritten. `author_document` itself and its tests stay as they are.
  - Update any exact-equality expectation in `test_catalog.py` whose authors carry a photo.

- [ ] **Step 4: Run the tests to make sure they pass**

Run the admin tests. Expected: everything passes, with no failures.

- [ ] **Step 5: Checkpoint.** `git status --short` should list only this task's files. Commit only if the owner asks: `fix(admin): migrate and rebuild keep approved poet photos`.

---

### Task 2: Security rules for photo records and Storage

**Files:**
- Modify: `firebase/firestore.rules`
- Create: `firebase/storage.rules`
- Modify: `firebase/firebase.json`
  - Add `"storage": {"rules": "storage.rules"}`.
  - Add the emulators `"storage": {"port": 9199}` and `"auth": {"port": 9099}`.
- Modify: `firebase/rules-tests/rules.test.mjs`. Add the `photoSubmissions` tests, and change the run comment at the top to `--only firestore,storage`.
- Create: `firebase/rules-tests/storage.test.mjs`

**Interfaces:**
- Produces: the rules that Task 6's Firebase store and Task 3's emulator tests run against. They allow the paths and the record shape in Global Constraints, and nothing more.

- [ ] **Step 1: Write the failing Firestore tests in `rules.test.mjs`**

```js
const reader = (uid, claims = {}) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'apple.com' }, ...claims }).firestore()
const googleReader = (uid) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'google.com' } }).firestore()
const anonymousReader = (uid) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).firestore()
const submission = (overrides = {}) =>
  ({ authorId: 7, submittedBy: 'alice', createdAt: serverTimestamp(), ...overrides })
```

Write these tests, each with `assertSucceeds` or `assertFails`:

- **'a signed-in reader can send and resend a photo record':** `setDoc(photoSubmissions/7_alice)` succeeds twice for `reader('alice')`, and for `googleReader('alice')`.
- **'anonymous, signed-out and banned readers cannot send a record':** the write fails for `anonymousReader('alice')`, for `anon()` and for `reader('alice', { photoBan: true })`.
- **'a record must match its ID and shape':** each of these fails for `reader('alice')`:
  - the ID `7_bob`;
  - `authorId: 8` at `7_alice`;
  - `submittedBy: 'bob'`;
  - `createdAt: Timestamp.now()`;
  - an extra field;
  - each of the three fields left out in turn;
  - `authorId: '7'`.
- **'a reader can get and delete only their own record, even when it doesn't exist':**
  - `getDoc` of a missing `7_alice` succeeds for alice, with `exists()` false.
  - `deleteDoc` of a missing `7_alice` succeeds for alice.
  - Both fail for `reader('bob')`.
  - A banned alice can still delete hers.
- **'nobody can list photo records':** `getDocs(collection(db, 'photoSubmissions'))` fails for alice, and so does a `where('submittedBy', '==', 'alice')` query.

- [ ] **Step 2: Write the failing Storage tests in `storage.test.mjs`**

Use the same setup as `rules.test.mjs`, but with `storage: { rules }` read from `../storage.rules`, `clearStorage()` in `beforeEach`, and `ref`, `uploadBytes`, `getBytes` and `deleteObject` from `firebase/storage`. Upload a JPEG stub `new Uint8Array([0xff, 0xd8, 0xff, 0xd9])` with `{ contentType: 'image/jpeg' }`.

- **'a signed-in reader can upload and overwrite their own photo':** `photo-submissions/7/alice.jpg` succeeds twice, with an `apple.com` token and with a `google.com` token.
- **'anonymous, signed-out and banned readers cannot upload'.**
- **'uploads go only to the reader's own file, as JPEG, up to 5 MB':**
  - `photo-submissions/7/bob.jpg` fails for alice.
  - `7/alice.png` fails.
  - `contentType: 'image/png'` fails.
  - `5 * 1024 * 1024 + 1` bytes fails, while exactly `5 * 1024 * 1024` succeeds.
  - `photo-submissions/x/alice.jpg` fails.
- **'only the sender can read and delete a waiting photo':**
  - `getBytes` succeeds for alice, and fails for bob and for an unauthenticated reader.
  - `deleteObject` succeeds for alice, including a banned alice.
- **'approved photos are public and no client can write them':**
  - Seed `poets/7.jpg` with rules disabled.
  - An unauthenticated `getBytes` succeeds.
  - An upload to `poets/7.jpg` fails for alice.
- **'everything else is denied':** an upload to, and a read of, `other/x.jpg` fail for alice.

- [ ] **Step 3: Run the rules tests to make sure they fail**

Expected: the new Firestore tests fail at their allow cases. The Storage file fails to start until `storage.rules` exists and `firebase.json` names it.

- [ ] **Step 4: Write the rules**

Both files use these helpers. Missing claims must be read with `.get`: reading a missing key directly is an error, and an error means "deny".

```
function canSendPhotos() {
  return request.auth != null
    && request.auth.token.firebase.sign_in_provider in ['apple.com', 'google.com']
    && request.auth.token.get('photoBan', false) != true;
}
```

**Firestore:**
- `match /photoSubmissions/{id}`:
  - **create, update:** `canSendPhotos()` plus a `validSubmission(id)`. It has exactly the three keys, with `authorId is int` and `submittedBy == request.auth.uid`. It also needs `createdAt == request.time` and `id == string(request.resource.data.authorId) + '_' + request.auth.uid`.
  - **get, delete:** `ownsSubmission(id)`, meaning `request.auth != null`, `id.split('_').size() == 2` and `id.split('_')[1] == request.auth.uid`. It tests the ID only, never `resource.data`.
  - **list:** never.

**Storage:**
- `service firebase.storage { match /b/{bucket}/o { … } }`.
- `match /photo-submissions/{authorId}/{file}`:
  - **create, update:** `canSendPhotos()`, `file == request.auth.uid + '.jpg'`, `authorId.matches('[0-9]+')`, `request.resource.contentType == 'image/jpeg'` and `request.resource.size <= 5 * 1024 * 1024`.
  - **read, delete:** `request.auth != null && file == request.auth.uid + '.jpg'`.
- `match /poets/{file}`: `allow read: if true;` and no write.

Reads by download token work without that `allow read`. It is there so the emulator tests can fetch approved photos with a plain GET. Approved photos are public anyway.

- [ ] **Step 5: Run the rules tests to make sure they pass**

Expected: every test passes, with `# fail 0`.

- [ ] **Step 6: Checkpoint.** `feat(firebase): rules for reader-sent poet photos`.

---

### Task 3: The admin tool approves, rejects and removes photos

**Files:**
- Modify: `firebase/admin/pyproject.toml` (add `"Pillow"` to `dependencies`), then `cd firebase/admin && .venv/bin/python -m pip install -e '.[dev]'`
- Create: `firebase/admin/wuserade_admin/photos.py`
- Modify: `firebase/admin/tests/conftest.py`
- Create: `firebase/admin/tests/test_photos_unit.py`, `firebase/admin/tests/test_photos_emulator.py`
- Modify: `firebase/admin/README.md`. Its `emulators:exec` command becomes `--only firestore,storage,auth`.

**Interfaces:**
- Consumes:
  - Task 1's meta entry shape.
  - Task 2's paths.
  - `store.connect()`, `store.EMULATOR_PROJECT_ID`, `store.PROJECT_ID` and `store.META_PATH`.
- Produces (in `photos.py`), for Task 4:
  ```python
  BUCKET = "wuserade.firebasestorage.app"
  EMULATOR_BUCKET = "demo-wuserade.appspot.com"
  PUBLIC_HOST = "https://firebasestorage.googleapis.com"

  @dataclass(frozen=True)
  class PhotoServices:
      db: firestore.Client
      bucket: storage.Bucket          # google.cloud.storage
      download_host: str              # PUBLIC_HOST, or the Storage emulator's http://host:port

  def connect() -> PhotoServices
  def parse_submission_id(submission_id: str) -> tuple[int, str]     # "12_uid" -> (12, "uid")
  def submission_path(author_id: int, uid: str) -> str               # "photo-submissions/12/uid.jpg"
  def publishable_jpeg(data: bytes, max_side: int = 1024) -> bytes
  def download_url(host: str, bucket: str, path: str, token: str) -> str
  def delete_submissions(services, *, author_id: int | None = None, uid: str | None = None) -> int
  def approve(services, submission_id: str, file: Path | None = None) -> str   # the new photoURL
  def reject(services, submission_id: str) -> None
  def remove(services, author_id: int) -> None
  ```
  Errors are `ValueError`s with a one-line message. `main` already prints them as `error: …` and returns 1.

- [ ] **Step 1: Check what the emulators set**

Run from `firebase/`:

```bash
npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore,storage,auth "env | grep -i emulator_host"
```

Expected: `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, and `STORAGE_EMULATOR_HOST=http://127.0.0.1:9199` and/or `FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199`. Read the Storage host from `STORAGE_EMULATOR_HOST`, or from `"http://" + FIREBASE_STORAGE_EMULATOR_HOST` when only that one is set.

- [ ] **Step 2: Write the failing unit tests in `test_photos_unit.py`** (no emulator needed)

The helper `jpeg_bytes(w, h, orientation=1, gps=False)` builds a test JPEG with Pillow. It writes an EXIF orientation tag (`0x0112`) and, with `gps`, a GPS IFD (`0x8825`) holding a latitude.

```python
def test_publishable_jpeg_shrinks_the_long_side_to_1024():
    out = Image.open(BytesIO(photos.publishable_jpeg(jpeg_bytes(3000, 2000))))
    assert out.format == "JPEG" and out.size == (1024, 683)

def test_publishable_jpeg_keeps_small_photos_their_size():
    assert Image.open(BytesIO(photos.publishable_jpeg(jpeg_bytes(500, 400)))).size == (500, 400)

def test_publishable_jpeg_applies_orientation_and_drops_exif():
    out = Image.open(BytesIO(photos.publishable_jpeg(jpeg_bytes(300, 100, orientation=6, gps=True))))
    assert out.size == (100, 300)
    assert len(out.getexif()) == 0

def test_publishable_jpeg_flattens_a_png_with_alpha():
    # an RGBA PNG goes in; the result is an RGB JPEG

def test_download_url():
    assert photos.download_url(photos.PUBLIC_HOST, photos.BUCKET, "poets/12.jpg", "tok") == (
        "https://firebasestorage.googleapis.com/v0/b/wuserade.firebasestorage.app/o/poets%2F12.jpg?alt=media&token=tok")

def test_parse_submission_id():
    assert photos.parse_submission_id("12_abc") == (12, "abc")
    for bad in ["", "12", "x_abc", "12_", "_abc", "12_a_b"]:
        with pytest.raises(ValueError):
            photos.parse_submission_id(bad)

def test_connect_refuses_a_partial_emulator_setup(monkeypatch):
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080")
    monkeypatch.delenv("STORAGE_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("FIREBASE_STORAGE_EMULATOR_HOST", raising=False)
    with pytest.raises(ValueError, match="firestore,storage,auth"):
        photos.connect()
```

The last test matters: with an emulator Firestore and no Storage or Auth emulator, `ban` would reach the production accounts.

- [ ] **Step 3: Add the fixtures and write the failing emulator tests**

**`conftest.py`** gains three fixtures:
- **`storage_bucket`:** skips without a Storage emulator host, and deletes every blob in `EMULATOR_BUCKET`.
- **`auth_emulator`:** skips without `FIREBASE_AUTH_EMULATOR_HOST`, and sends `DELETE http://{host}/emulator/v1/projects/demo-wuserade/accounts`.
- **`services(db, storage_bucket, auth_emulator)`:** returns `photos.connect()`.

**Helpers in `test_photos_emulator.py`:**
- `seed_poet(db, 7)` writes `authors/7` (`name "Author 7"`) and a `meta/content` that holds a catalog version and an entry for poet 7.
- `seed_submission(services, 7, "alice", size=(2000, 1000))` uploads a JPEG to `submission_path(7, "alice")` and writes the record `7_alice`.

**Tests:**
- **`test_approve_publishes_and_updates_both_places`:**
  - The blob `poets/7.jpg` exists.
  - Its `content_type` is `"image/jpeg"`, its long side is at most 1024, and its `cache_control` is `"public, max-age=31536000"`.
  - `authors/7.photoURL == url`, the meta entry for 7 has `photoURL == url`, and the meta `catalogVersion` is unchanged.
  - `url` starts with `services.download_host`, and `urlopen(url).read()` returns the blob's bytes.
- **`test_approve_clears_every_waiting_submission_for_that_poet`:** seed `7_alice`, `7_bob` and `8_carol`. After approving `7_alice`, both `7_` records and their files are gone, and `8_carol` remains.
- **`test_approve_with_file_publishes_the_owners_copy`:** an 800×800 file passed with `file=` is published at 800×800.
- **`test_approve_again_changes_the_url`** (Review Focus 5):
  1. Approving `7_alice` gives `url1`.
  2. Seed `7_bob` and approve it, which gives `url2`.
  3. `url2 != url1`, and meta and `authors/7` hold `url2`.
- **`test_reject_deletes_the_record_and_file`.**
- **`test_reject_unknown_submission_raises`:** `ValueError`.
- **`test_remove_clears_the_photo_everywhere`:** after an approve, `remove(services, 7)` leaves `authors/7.photoURL` as None, no `photoURL` key in the meta entry, and no blob `poets/7.jpg`.
- **`test_approve_for_a_poet_missing_from_meta_raises_and_changes_nothing`:** `ValueError`, no `poets/` blob, and the submission is still there.

- [ ] **Step 4: Run the tests to make sure they fail**

Run the admin tests. Expected: the new tests fail with `AttributeError` or `ImportError` for `photos`.

- [ ] **Step 5: Implement `photos.py`**

**`connect()`:**
- **In production:** the Firestore client from `store.connect()`, and `firebase_admin.storage.bucket(BUCKET)` on the default app, which `store.connect()` initializes. The host is `PUBLIC_HOST`.
- **Under `FIRESTORE_EMULATOR_HOST`:**
  - Require the Storage and Auth emulator hosts too, or raise `ValueError("run through emulators:exec --only firestore,storage,auth")`.
  - Use `google.cloud.storage.Client(project=store.EMULATOR_PROJECT_ID, credentials=AnonymousCredentials()).bucket(EMULATOR_BUCKET)`.
  - Make sure a default `firebase_admin` app exists with `projectId` `demo-wuserade`, for `firebase_admin.auth` in Task 4.

**`publishable_jpeg`:** Pillow `ImageOps.exif_transpose`, then convert to RGB, then `thumbnail((max_side, max_side), LANCZOS)`, then save as JPEG at quality 85 with no `exif=`.

**`approve`:**
1. Check everything before the first write:
   - The record exists.
   - `authors/{id}` exists.
   - The poet has an entry in `meta/content.authors`.
2. Upload the processed image to `poets/{id}.jpg`:
   - Bytes from the submission's file, or from `file`.
   - `metadata = {"firebaseStorageDownloadTokens": uuid4().hex}`.
   - `cache_control = "public, max-age=31536000"`.
   - `content_type="image/jpeg"`.
3. In one `@firestore.transactional` function, set `authors/{id}.photoURL` and that poet's meta entry `photoURL`. Don't touch anything else in meta: no rebuild, and the version stays.
4. Run `delete_submissions(author_id=id)`. It deletes the records found by the query `authorId == id` (the Admin SDK may query), and every blob under the prefix `photo-submissions/{id}/`, so orphaned files go too.

The new token on every approval is what gives a replaced photo a new URL (Review Focus 5).

**`remove`:**
- In one transaction, set `authors/{id}.photoURL` to None and drop the key from the meta entry.
- Then delete `poets/{id}.jpg` if it is there.

- [ ] **Step 6: Run the tests to make sure they pass**

Run the admin tests. Expected: all of them pass. The emulator ones run, not skip; check with `-rs` if unsure.

- [ ] **Step 7: Checkpoint.** `feat(admin): approve, reject and remove poet photos`.

---

### Task 4: The admin tool lists photos and blocks senders, plus the `photos` CLI

**Files:**
- Modify: `firebase/admin/wuserade_admin/photos.py`
- Modify: `firebase/admin/wuserade_admin/__main__.py` (the `photos` subcommands)
- Modify: `firebase/admin/tests/test_photos_emulator.py`, `firebase/admin/tests/test_cli_emulator.py`
- Modify: `firebase/admin/README.md` (a "Poet photos" section with the commands below and the report procedure: `photos remove`, then `photos ban` if needed)

**Interfaces:**
- Consumes: everything Task 3 produces.
- Produces:
  ```python
  @dataclass(frozen=True)
  class Submission:
      id: str; author_id: int; uid: str; poet_name: str; created_at: datetime; path: Path
  def list_submissions(services, out_dir: Path) -> list[Submission]   # oldest first
  def ban(services, uid_or_submission_id: str) -> int                # waiting photos deleted
  def unban(services, uid: str) -> None
  ```
- CLI:
  - `photos list [--out DIR]` (default `~/Downloads/wuserade-photos`)
  - `photos approve SUBMISSION_ID [--file PATH]`
  - `photos reject SUBMISSION_ID`
  - `photos remove AUTHOR_ID`
  - `photos ban UID_OR_SUBMISSION_ID`
  - `photos unban UID`

  `ban` takes either: an ID with one `_` is a submission ID, and its uid part is used. Firebase uids contain no `_`.

- [ ] **Step 1: Write the failing tests**

In `test_photos_emulator.py`:
- **`test_list_downloads_each_waiting_photo`:**
  - Seed `7_alice` for "Author 7", then `8_bob` later.
  - The result is two `Submission`s, oldest first.
  - The files are `7-Author 7-alice.jpg` and `8-Author 8-bob.jpg` in `tmp_path`, with the uploaded bytes.
  - The file name has the poet name, with `/`, `\` and `:` replaced by `-`, and the first six characters of the uid.
- **`test_ban_sets_the_claim_revokes_tokens_and_deletes_waiting_photos`:**
  - Create alice with `firebase_admin.auth.create_user(uid="alice")`.
  - Seed `7_alice`, `8_alice` and `7_bob`.
  - `ban(services, "alice") == 2`.
  - Alice's claims include `photoBan: True`, and her `tokens_valid_after_timestamp` is later than before.
  - `7_bob` remains.
- **`test_ban_takes_a_submission_id_and_keeps_other_claims`:** alice starts with the claim `{"x": 1}`. After `ban(services, "7_alice")`, her claims are `{"x": 1, "photoBan": True}`.
- **`test_unban_removes_only_the_claim`.**

In `test_cli_emulator.py`, in that file's style:
- **`test_cli_photos_approve_reject_and_errors`:**
  - `cli.main(["photos", "approve", "7_alice"]) == 0`, and stdout contains `approved 7_alice`.
  - `cli.main(["photos", "reject", "9_nobody"]) == 1`, and stderr starts with `error:`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run the admin tests. Expected: the new tests fail.

- [ ] **Step 3: Implement**

**`ban`:** set the claims to the existing claims plus `photoBan: True`, then `revoke_refresh_tokens(uid)`, then `delete_submissions(uid=uid)`.

**`list_submissions`:** read the records ordered by `createdAt` and the poet names from `authors/{id}`, then download each file.

**The CLI prints:**
- **`list`:** one `{id}  {poet name}  {YYYY-MM-DD HH:MM}` line per photo, then `{n} waiting photos in {dir}`.
- **`approve`:** `approved {id}: {url}`.
- **`reject`:** `rejected {id}`.
- **`remove`:** `removed the photo of poet {id}`.
- **`ban`:** `banned {uid}; deleted {n} waiting photos`.
- **`unban`:** `unbanned {uid}`.

Each handler connects with `photos.connect()` and returns 0.

- [ ] **Step 4: Run the tests to make sure they pass**

Run the admin tests. Expected: all of them pass.

- [ ] **Step 5: Checkpoint.** `feat(admin): list waiting photos and block senders`.

---

### Task 5: The app reads approved photos

**Files:**
- Modify: `Wuserade.xcodeproj/project.pbxproj`. Add the `FirebaseStorage` product by copying the four `FirebaseFirestore` entries with fresh 24-hex IDs and the same package reference:
  - the PBXBuildFile (line 11);
  - the Frameworks phase (line 92);
  - `packageProductDependencies` (line 226);
  - the XCSwiftPackageProductDependency (line 740).

  Then run `plutil -lint`.
- Modify: `wuserade/Models/ContentMeta.swift`
- Modify: `wuserade/Catalog/Library.swift`
- Modify: `wuserade/Models/Author.swift`
- Modify: `wuserade/Lists/PoetsView.swift`. Use `isUnknownAuthor` and delete `unknownName`.
- Test: `wuseradeTests/AuthorEntryTests.swift`, `wuseradeTests/LibraryPhotoTests.swift`, `wuseradeTests/AuthorTests.swift` (all new)

**Interfaces:**
- Produces:
  ```swift
  struct AuthorEntry { var photoURL: String? = nil }      // `var` with a default, so it is decoded
  extension Library {
      func photoURL(ofPoet id: Int) -> URL?                 // nil unless an absolute http(s) URL is in meta
      func poetIDs() async throws -> [Int]                  // every author in meta; refreshes once if meta is nil
  }
  extension Author { var isUnknownAuthor: Bool }           // KabardianText.searchKey(name) == searchKey("Зытхар тщӀэкъым")
  ```
  `poetIDs()` throws `store.lastError ?? LibraryError.notLoaded`, like `search(_:)` does.

- [ ] **Step 1: Write the failing tests**

**`AuthorEntryTests`:**
- **`testDecodesPhotoURL`:** `{"id":7,"name":"А","poemsCount":3,"photoURL":"https://x/7.jpg"}` gives `"https://x/7.jpg"`.
- **`testMissingOrNullPhotoURLIsNil`:** both the missing and the `null` variants give nil.
- **`testCachedMetaWithoutPhotosStillDecodes`:** a whole `ContentMeta` JSON from before the change decodes.

**`LibraryPhotoTests`** builds `CatalogStore(repository: FakeContentRepository(meta:), cache: CatalogCache(directory: <temp>))` as `CatalogStoreTests.makeStore` does:
- **`testPhotoURLOfPoet`:**
  - Meta authors: 7 with `"https://x/7.jpg"`, 8 with none, and 9 with `"authors/9.jpg"`.
  - After `await store.refresh()`, poet 7 gives `URL(string: "https://x/7.jpg")`.
  - Poets 8, 9 and 42 give nil.
- **`testPoetIDsLoadsMetaWhenMissing`:** authors 7 and 8, on a fresh store. The result is `[7, 8]`, and the fake's `metaCalls == 1`.
- **`testPoetIDsThrowsWhenMetaCannotLoad`:** the fake's meta read fails. Add a `failMeta` switch to `FakeContentRepository` if it has none. `poetIDs()` throws.

**`AuthorTests`:**
- **`testUnknownAuthor`:** true for `"Зытхар тщ\u{04C0}экъым"` and for the `\u{04CF}` spelling, and false for `"Author 7"`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run the Swift tests for `AuthorEntryTests`, `LibraryPhotoTests` and `AuthorTests`. Expected: `** TEST FAILED **`, with errors about `photoURL`, `poetIDs` and `isUnknownAuthor`.

- [ ] **Step 3: Implement.** Use `PoetsView`'s current test in `isUnknownAuthor`, then switch `PoetsView` over to it.

- [ ] **Step 4: Run the tests to make sure they pass.** Run all three classes, and then the full suite. Expected: `** TEST SUCCEEDED **` both times; the full suite includes `CatalogStoreTests`.

- [ ] **Step 5: Checkpoint.** `feat(ios): read approved poet photos from meta`.

---

### Task 6: `PhotoSubmissions` and its Firebase store

**Files:**
- Create in `wuserade/Services/Photos/`:
  - `PhotoSubmissionStore.swift`
  - `PhotoSubmissionError.swift`
  - `WaitingStatus.swift`
  - `FirebasePhotoSubmissionStore.swift`
  - `PhotoSubmissions.swift`
- Modify: `wuserade/wuseradeApp.swift`
- Modify: `wuseradeTests/Fakes.swift` (`FakePhotoSubmissionStore`, with a lock like the other fakes)
- Test: `wuseradeTests/PhotoSubmissionsTests.swift`, `wuseradeTests/FirebasePhotoSubmissionStoreTests.swift`

**Interfaces:**
- Consumes: `Library.poetIDs()` and `AccountState`.
- Produces:
  ```swift
  protocol PhotoSubmissionStore: Sendable {
      func isWaiting(authorId: Int, uid: String) async throws -> Bool   // photoSubmissions/{authorId}_{uid} exists
      func send(_ jpeg: Data, authorId: Int, uid: String) async throws  // upload (image/jpeg), then the record
      func delete(authorId: Int, uid: String) async throws              // file, then record; missing counts as deleted
  }
  enum PhotoSubmissionError: Error, Equatable { case banned, notSignedIn }
  enum WaitingStatus: Equatable { case unchecked, waiting, notWaiting, failed }

  @MainActor @Observable final class PhotoSubmissions {
      init(store: any PhotoSubmissionStore, poetIDs: @escaping @MainActor () async throws -> [Int])
      private(set) var uid: String?
      static func uid(for state: AccountState) -> String?    // the uid only when .signedIn
      func bind(uid: String?)                                // a different uid forgets every status
      func status(poetID: Int) -> WaitingStatus              // the spec's isWaiting(poetID:)
      func isSending(poetID: Int) -> Bool
      func check(poetID: Int) async                          // one isWaiting; errors -> .failed; no uid -> nothing
      func send(_ jpeg: Data, for poetID: Int) async throws  // ignored while one is sending; success -> .waiting
      func deleteAll(uid: String) async throws               // delete for every poetIDs(); then forgets statuses
  }
  ```
  `FirebasePhotoSubmissionStore` has two error helpers:
  - `static func mapped(_ error: Error) -> Error` turns a Storage `unauthorized` or a Firestore `permissionDenied` into `PhotoSubmissionError.banned`, and passes anything else through unchanged.
  - `static func isNotFound(_ error: Error) -> Bool` is true for Storage `objectNotFound`.

  Compare errors through `NSError` domain and code.

- [ ] **Step 1: Write the failing tests**

**`FakePhotoSubmissionStore`** has these settable properties:
- `waiting: Set<String>` (keys like `"7_alice"`)
- `isWaitingError`, `sendError` and `deleteError`
- `sendDelay: Duration?`

It records `calls: [String]` such as `"isWaiting 7_alice"`, `"send 7_alice"` and `"delete 7_alice"`.

**`PhotoSubmissionsTests`:**
- **`testUidForState`** (Review Focus 1): `.signedOut` gives nil, `.anonymous(uid: "a")` gives nil, and `.signedIn(uid: "a", provider: .apple, email: nil)` gives `"a"`.
- **`testCheckReadsTheRecord`:** bound to `"alice"` with `waiting` set to `["7_alice"]`. After checks, poet 7 is `.waiting` and poet 8 is `.notWaiting`.
- **`testCheckFailureIsFailed`.**
- **`testCheckWithoutUidDoesNothing`:** no calls, and the status stays `.unchecked`.
- **`testSendMarksTheRecordWaiting`:** the status is `.waiting`, and the calls are `["send 7_alice"]`.
- **`testFailedSendKeepsStatusAndRethrows`:** after a check, the status stays `.notWaiting`, the error is rethrown, and `isSending(poetID: 7)` is false.
- **`testSendWithoutUidThrowsNotSignedIn`.**
- **`testSecondSendWhileSendingIsIgnored`** (Review Focus 2): with `sendDelay` at 200 ms, start one send, then call `send` again before it finishes. The store gets exactly one `send` call.
- **`testBindToAnotherUidForgetsStatuses`** (Review Focus 1): alice's 7 is `.waiting`. After `bind(uid: "bob")`, 7 is `.unchecked`, and a check asks for `7_bob`.
- **`testBindToTheSameUidKeepsStatuses`.**
- **`testDeleteAllDeletesEveryPoetsRecord`:** with `poetIDs` of `[7, 8, 9]`, the calls hold `delete 7_alice`, `delete 8_alice` and `delete 9_alice`, in any order.
- **`testDeleteAllRethrowsWhenPoetIDsFail`.**
- **`testDeleteAllRethrowsWhenADeleteFails`.**

**`FirebasePhotoSubmissionStoreTests`:**
- **`testUnauthorizedUploadMeansBanned`:** `NSError(domain: StorageErrorDomain, code: StorageErrorCode.unauthorized.rawValue)` gives `.banned`.
- **`testPermissionDeniedRecordMeansBanned`:** `FirestoreErrorCode(.permissionDenied)` gives `.banned`.
- **`testOtherErrorsPassThrough`.**
- **`testObjectNotFoundIsNotFound`:** true for `objectNotFound`, and false for `unauthorized`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run `PhotoSubmissionsTests` and `FirebasePhotoSubmissionStoreTests`. Expected: `** TEST FAILED **`, with missing types.

- [ ] **Step 3: Implement**

**The Firebase store:**
- `Storage.storage().reference(withPath:)`, then `putDataAsync` with `StorageMetadata` whose `contentType` is `"image/jpeg"`.
- Then `setData(["authorId": authorId, "submittedBy": uid, "createdAt": FieldValue.serverTimestamp()])`.
- `delete` ignores `isNotFound` errors.
- Run every thrown error through `mapped`.

**`deleteAll`:** delete the poets concurrently in a task group.

**Wiring in `wuseradeApp.swift`:**
- Create `@State private var photos` in `init()`: `PhotoSubmissions(store: FirebasePhotoSubmissionStore(), poetIDs: { [library] in try await library.poetIDs() })`.
- Add `.environment(photos)`.
- Add `.onChange(of: account.state, initial: true) { photos.bind(uid: PhotoSubmissions.uid(for: account.state)) }`.

Observe the whole state, never `account.state.uid`. Linking an anonymous account to Apple keeps its uid, so a `.uid` observer would miss the sign-in (Review Focus 1).

- [ ] **Step 4: Run the tests to make sure they pass.** Run both classes, then the full suite. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Checkpoint.** `feat(ios): track and send waiting poet photos`.

---

### Task 7: Deleting an account deletes its waiting photos

**Files:**
- Modify: `wuserade/Services/Account/AccountManager.swift`
- Modify: `wuserade/wuseradeApp.swift`. Move `account`'s creation from its property initializer into `init()`, after `photos`.
- Modify: `wuserade/Settings/AccountSection.swift`, where the delete dialog's message adds the new slot.
- Modify: `wuserade/Text/OwnerCopy.swift`: `static let deletesWaitingPhotos = "[owner copy: photos you sent that are still waiting are deleted too]"`
- Modify: `wuseradeTests/Fakes.swift` (`FakePhotoDeleter`)
- Modify: `wuseradeTests/AccountManagerTests.swift`
- Modify: every other `AccountManager(` call site. Check with `grep -rn "AccountManager(" wuserade wuseradeTests`.

**Interfaces:**
- Consumes: `PhotoSubmissions.deleteAll(uid:)`.
- Produces: an `AccountManager.init` parameter, `deleteWaitingPhotos: @escaping @MainActor (_ uid: String) async throws -> Void`. It has no default, so production wiring can't be forgotten. `performDeleteAccount` calls it after `likes.deleteAllData(uid:)` and before `auth.deleteCurrentUser(expectedUID:)`. Nothing else calls it; the anonymous-account cleanups during a sign-in merge don't.

- [ ] **Step 1: Write the failing tests**

**`FakePhotoDeleter(log: CallLog)`** has `var error: Error?`, used while it is set, and `private(set) var deletedUids: [String]`. Its `deleteAll(uid:)` records `"deleteWaitingPhotos"`. `makeEnv` creates one and passes `deleteWaitingPhotos: { try await deleter.deleteAll(uid: $0) }`, and `Env` gains `photos`.

**Changes to existing tests:**
- **`testDeleteAppleAccountCallOrder`:** expects `"reauthenticate", "revokeAppleToken", "deleteAllData", "deleteWaitingPhotos", "deleteCurrentUser", "signInAnonymously", "ensureUserDocument"`, and `env.photos.deletedUids == ["apple-user"]`.
- **`testDeleteGoogleAccountSkipsRevoke`:** the same insertion.

The merge tests' expectations at lines 144 and 254 stay as they are. That proves a merge never deletes photos.

**New test:** `testDeleteAccountStopsWhenWaitingPhotosCannotBeDeleted` (Review Focus 3):
1. Set `env.photos.error` to `FakeLikesStore.Failure()`.
2. `deleteAccount` throws, `env.auth.deletedUids == []`, and the state is still `.signedIn(uid: "apple-user", …)`.
3. Clear the error and retry.
4. Now `deletedUids == ["apple-user"]` and the state is `.anonymous(uid: "anon-1")`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run `AccountManagerTests`. Expected: a compile error about the missing argument.

- [ ] **Step 3: Implement**

- **`wuseradeApp`:** pass `deleteWaitingPhotos: { [photos] uid in try await photos.deleteAll(uid: uid) }`.
- **Delete dialog:** its message becomes `Text("\(Self.deleteWarning) \(OwnerCopy.deletesWaitingPhotos)")`.

- [ ] **Step 4: Run the tests to make sure they pass**

Run `AccountManagerTests`, then the full suite. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Checkpoint.** `feat(ios): delete waiting photos with the account`.

---

### Task 8: Preparing a picked photo

**Files:**
- Create: `wuserade/Services/Photos/PhotoPreparation.swift`, `wuserade/Services/Photos/PreparedPhoto.swift`
- Test: `wuseradeTests/PhotoPreparationTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct PreparedPhoto: Identifiable { let id: UUID; let jpeg: Data; let image: CGImage }
  enum PhotoPreparation {
      enum Failure: Error, Equatable { case unreadable, unencodable }
      static let maxPixelSize = 2000
      static let quality = 0.85
      nonisolated static func prepare(_ data: Data) throws -> PreparedPhoto   // run it off the main actor
  }
  ```

- [ ] **Step 1: Write the failing tests**

The helper `makeJPEG(width:height:orientation:withMetadata:) -> Data` writes a JPEG with `CGImageDestination`. With metadata, it adds `kCGImagePropertyOrientation`, a GPS dictionary (latitude 43.5 N), Exif `DateTimeOriginal` and TIFF `Make: "TestCam"`.

- **`testLongSideIsAtMost2000`:** 4000×3000 becomes 2000×1500.
- **`testPanoramaKeepsItsShape`** (Review Focus 4): 12000×1000 becomes 2000 wide and 166 or 167 high.
- **`testSmallPhotoIsNotEnlarged`** (Review Focus 4): 300×200 stays 300×200.
- **`testOrientationIsApplied`:** 400×200 with orientation 6 becomes 200×400, and the output orientation is absent or 1.
- **`testNoMetadataSurvives`:** the output's `CGImageSourceCopyPropertiesAtIndex` has no GPS dictionary, no TIFF `Make` and no Exif `DateTimeOriginal`.
- **`testOutputIsJPEG`:** `CGImageSourceGetType` gives `UTType.jpeg.identifier`.
- **`testUnreadableDataThrows`** (Review Focus 4): `Data("not an image".utf8)` throws `.unreadable`.

- [ ] **Step 2: Run the tests to make sure they fail.** Run `PhotoPreparationTests`. Expected: `** TEST FAILED **`.

- [ ] **Step 3: Implement**

1. Read the data with `CGImageSourceCreateWithData`.
2. Make the image with `CGImageSourceCreateThumbnailAtIndex(source, 0, …)`, passing:
   - `kCGImageSourceCreateThumbnailFromImageAlways: true`, so a small embedded preview is never used;
   - `kCGImageSourceCreateThumbnailWithTransform: true`;
   - `kCGImageSourceThumbnailMaxPixelSize: maxPixelSize`.
3. Encode it with `CGImageDestinationCreateWithData(…, UTType.jpeg.identifier as CFString, 1, nil)` and `CGImageDestinationAddImage` with only `kCGImageDestinationLossyCompressionQuality`. Nothing from the source's properties is passed on, so no metadata is written.

- [ ] **Step 4: Run the tests to make sure they pass.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Checkpoint.** `feat(ios): shrink picked photos and strip their metadata`.

---

### Task 9: The poet page's round portrait

**Files:**
- Modify: `Wuserade.xcodeproj/project.pbxproj`. Add a `Photos` `PBXFileSystemSynchronizedRootGroup`, copying the three entries of `Catalog` (`D0A1E5000000000000000001`) with an unused ID from the same series:
  - the root group;
  - the `wuserade` group's `children`;
  - the app target's `fileSystemSynchronizedGroups`.

  Then run `plutil -lint`.
- Create in `wuserade/Photos/`:
  - `PoetInitials.swift`
  - `PoetPortrait.swift`
  - `PortraitLoader.swift`
  - `SendAreaState.swift`
  - `SendPhotoArea.swift`
  - `PoetHeader.swift`
- Modify: `wuserade/Lists/PoemCollectionView.swift`, `wuserade/Lists/PoetView.swift`, `wuserade/Settings/AppLinks.swift`
- Modify: `wuserade/Text/OwnerCopy.swift`. Add these slots, spelled exactly:
  - `photoOfPoet = "[owner copy: photo of the poet]"`
  - `reportPhoto = "[owner copy: report this photo]"`
  - `reportSubject = "[owner copy: photo report]"`
  - `sendPhoto = "[owner copy: send a photo]"`
  - `photoWaiting = "[owner copy: photo sent, waiting for review]"`
- Test: `wuseradeTests/PoetInitialsTests.swift`, `wuseradeTests/SendAreaStateTests.swift`, `wuseradeTests/PhotoReportTests.swift`

**Interfaces:**
- Consumes: `Library.photoURL(ofPoet:)`, `Author.isUnknownAuthor`, `PhotoSubmissions`, `WaitingStatus` and `AccountManager`.
- Produces:
  ```swift
  enum PoetInitials { static func of(_ name: String) -> String }  // sectionLetter(of:) of each of the first two words
  struct PoetPortrait: View { static let diameter: CGFloat = 128; let initials: String; let image: CGImage? }
  enum PortraitLoader { static func image(at url: URL) async throws -> CGImage }
  enum SendAreaState: Equatable {
      case button, waiting, hidden
      static func resolve(hasPhoto: Bool, isSignedIn: Bool, waiting: WaitingStatus) -> SendAreaState
  }
  struct SendPhotoArea: View { let poet: Author; let hasPhoto: Bool }   // Task 10 adds the flow behind the button
  struct PoetHeader: View { let poet: Author; let count: Int? }
  extension AppLinks { static func photoReport(poetName: String, poetID: Int) -> URL }
  ```
  `PoemCollectionView` becomes generic, `PoemCollectionView<Header: View>`, with `@ViewBuilder let header: (_ count: Int?) -> Header`. An `extension … where Header == DetailHeader` keeps today's initializer, so `ThemeView` doesn't change. The list branch shows `header(poems.count)`, and the empty, loading and offline branches show `header(nil)`.

- [ ] **Step 1: Write the failing tests**

**`PoetInitialsTests`:**
- `"Хьа Бэ"` gives `"ХьБ"`.
- `"Кхъу"` gives `"Кхъ"`.
- `"  Бэ   Мы  "` gives `"БМ"`.
- `"Бэ Мы Щы"` gives `"БМ"`.
- `"хьа бэ"` gives `"ХьБ"`.
- `"К\u{04CF}уэ Бэ"` gives `"К\u{04C0}Б"`.
- `""` gives `""`.

**`SendAreaStateTests`**, one test per row:

| hasPhoto | isSignedIn | waiting | result |
|---|---|---|---|
| true | any | any | `.hidden` |
| false | false | any | `.button` |
| false | true | `.notWaiting` | `.button` |
| false | true | `.waiting` | `.waiting` |
| false | true | `.failed` | `.hidden` |
| false | true | `.unchecked` | `.hidden` |

The last row is my call: a signed-in reader doesn't see the button flash and then turn into the waiting line.

**`PhotoReportTests`:** `AppLinks.photoReport(poetName: "Author 7", poetID: 7)` has:
- scheme `mailto`;
- the path of `AppLinks.email`;
- the query item `subject == "\(OwnerCopy.reportSubject) Author 7 (7)"`;
- `body == "7"`.

Read the query items back through `URLComponents`.

- [ ] **Step 2: Run the tests to make sure they fail.** Run the three classes. Expected: `** TEST FAILED **`.

- [ ] **Step 3: Implement**

**`PortraitLoader`:**
- One static `URLSession` whose `urlCache` is `URLCache(memoryCapacity: 4_000_000, diskCapacity: 50_000_000, directory: <Caches>/Portraits)`, with `requestCachePolicy = .returnCacheDataElseLoad`.
- A response other than 2xx throws.
- Decode the data with `CGImageSource`.

Each approval has a new URL, so a cached photo never goes stale.

**`PoetPortrait`:**
- A circle of `diameter`.
- **With no image:** `Palette.accentWash` fill with the initials in `Palette.accent`, set in `.font(.custom(SerifFace.Cut.medium.rawValue, fixedSize: 44))`. The size is fixed because the circle is.
- **With an image:** `Image(decorative:scale:)` set to `scaledToFill`, clipped to the circle, with a 1 pt `Palette.hairline` ring.

**`PoetHeader`:**
- A centred `VStack(spacing: 0)` with `frame(maxWidth: .infinity)`, holding the portrait, then the name, the count and the send area:
  - **Name:** `.serif(.headerTitle)`, `ink`, centred, with the header trait, `Space.six` below the portrait.
  - **Count:** `"\(count) \(OwnerCopy.countNoun)"` in `.serif(.sectionLabel)`, `inkSecondary`, `Space.two` below the name. It is only there when `count` is not nil.
  - **Send area:** `SendPhotoArea(poet:hasPhoto:)`, `Space.four` below the count.
- The same top and bottom padding as `DetailHeader`.
- **Loading the photo:** `.task(id: photoURL)`, then set it `withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25))`. On failure, keep the initials.
- **Accessibility when a photo shows:**
  - `.accessibilityElement()`, `.accessibilityLabel(OwnerCopy.photoOfPoet)` and `.accessibilityAddTraits(.isImage)`.
  - `.contextMenu` with a `reportPhoto` button, plus `.accessibilityAction(named: OwnerCopy.reportPhoto)`.
  - Both open `AppLinks.photoReport` with `openURL`.
- **Without a photo:** `.accessibilityHidden(true)`.

**`SendPhotoArea`:**
- It shows the state from `SendAreaState.resolve` with `isSignedIn: PhotoSubmissions.uid(for: account.state) != nil`:
  - **Button:** `OwnerCopy.sendPhoto` with `.secondaryCapsule`. Its action stays empty until Task 10.
  - **Waiting line:** `OwnerCopy.photoWaiting` in `.serif(.rowSubtitle)`, `inkSecondary`, centred.
  - **Hidden:** `EmptyView`.
- It runs `.task(id: photos.uid) { if !hasPhoto { await photos.check(poetID: poet.id) } }`.

**`PoetView`:** `poet.isUnknownAuthor` keeps the default `DetailHeader` initializer. Every other poet gets `PoemCollectionView(…) { PoetHeader(poet: poet, count: $0) }`. Keep `.analyticsScreen` on the whole view.

- [ ] **Step 4: Run the tests to make sure they pass, then look**

Run the three classes and the full suite. Expected: `** TEST SUCCEEDED **`.

Build and launch on the simulator, and open three poet pages:
- A poet's page shows the circle with initials, the name, the count and the button, centred.
- "Зытхар тщӀэкъым" keeps the plain header.
- Check night mode, an AX text size and the iPad split view (the header centred in the content column). Take screenshots.

- [ ] **Step 5: Checkpoint.** `feat(ios): round portrait on the poet page`.

---

### Task 10: Sending a photo

**Files:**
- Create in `wuserade/Settings/`:
  - `SignInButtons.swift`
  - `AppleIDButton.swift`, moved out of `AccountSection.swift` and made internal
  - `AccountAlert.swift`
- Modify: `wuserade/Settings/AccountSection.swift`
- Modify: `wuseradeTests/AccountAlertTests.swift`, which now calls `AccountAlert.message(for:)`, `.configurationMessage` and `.genericMessage`.
- Create: `wuserade/Photos/PhotoSignInSheet.swift`, `wuserade/Photos/PhotoSendSheet.swift`
- Modify: `wuserade/Photos/SendPhotoArea.swift`
- Modify: `wuserade/Text/OwnerCopy.swift`. Add these slots, spelled exactly:
  - `signInToSendPhoto = "[owner copy: sign in to send a photo]"`
  - `whySendingNeedsAccount = "[owner copy: why sending needs an account]"`
  - `photoRights = "[owner copy: send only photos you have the right to share]"`
  - `send = "[owner copy: send]"`
  - `photoSendFailed = "[owner copy: photo could not be sent, try again]"`
  - `photoSendBanned = "[owner copy: this account can't send photos]"`
- Test: `wuseradeTests/PhotoSendSheetTests.swift`

**Interfaces:**
- Consumes: Tasks 6, 8 and 9.
- Produces:
  ```swift
  enum AccountAlert {   // moved verbatim from AccountSection: the texts and their TODO(owner) comments
      static func message(for error: Error) -> String?
      static let configurationMessage: String
      static let genericMessage: String
      static let title: String
      static let ok: String
  }
  struct SignInButtons: View      // Apple and Google, today's flow and alert; disabled while it runs or account.isBusy
  struct PhotoSignInSheet: View
  struct PhotoSendSheet: View {
      let poet: Author; let photo: PreparedPhoto
      struct FailureMessage: Equatable { let text: String; let canRetry: Bool }
      static func failureMessage(for error: Error) -> FailureMessage
  }
  ```

- [ ] **Step 1: Write the failing tests**

**`PhotoSendSheetTests`:**
- **`testBannedHasNoRetry`:** `.banned` gives `FailureMessage(text: OwnerCopy.photoSendBanned, canRetry: false)`.
- **`testOtherErrorsCanRetry`:** gives `(photoSendFailed, true)`.

**`AccountAlertTests`:** point the existing assertions at `AccountAlert`.

- [ ] **Step 2: Run the tests to make sure they fail.** Run `PhotoSendSheetTests` and `AccountAlertTests`. Expected: `** TEST FAILED **`.

- [ ] **Step 3: Move the sign-in buttons out of `AccountSection`**

**`SignInButtons`** takes `signInButtons`, `signIn(with:)`, `requestCredential`, `run` and `show(error)` from `AccountSection`. That includes the `await account.start()` after a failure, with its own `isWorking`.

**`AccountSection` keeps:**
- the explanation line above `SignInButtons()`;
- sign-out and delete, with its own `isWorking` and `run`;
- the delete flow's alert, through `AccountAlert`.

The Settings screen must look and behave as it does today.

- [ ] **Step 4: Build the sheets**

**`PhotoSignInSheet`:**
- A `NavigationStack` with a `ScrollView`, holding:
  - **Title:** `signInToSendPhoto` in `.serif(.emptyTitle)`.
  - **Note:** `whySendingNeedsAccount` in footnote, `inkSecondary`.
  - **Buttons:** `SignInButtons()`.
- A `CloseButton` in the toolbar.
- `.presentationDetents([.medium, .large])`, `.presentationDragIndicator(.visible)` and `FormSheetSizing()`.

The `.large` detent is my call, so accessibility text sizes fit.

**`PhotoSendSheet`:**
- The same shell, holding:
  - `PoetPortrait(initials:image: photo.image)`;
  - the poet's name in `.serif(.emptyTitle)`;
  - `photoRights` in `.serif(.prose)`, `inkSecondary`;
  - the failure text in footnote, `Palette.destructive`, when there is one;
  - the Send button with `.primaryCapsule(fullWidth: true)`. It shows a `ProgressView` while sending, and is disabled while sending or when `canRetry` is false.
- `.interactiveDismissDisabled(isSending)`.
- **On success:** dismiss, then post `AccessibilityNotification.Announcement(OwnerCopy.photoWaiting)`.

- [ ] **Step 5: Wire the flow in `SendPhotoArea`**

1. **Tap:** when signed in, `isPickerPresented = true`; otherwise `isSignInPresented = true`.
2. **Sign-in:** `.onChange(of: account.state)` closes the sign-in sheet when the state becomes `.signedIn`. The sheet's `onDismiss` opens the picker if the reader is signed in by then.

   Open the picker from `onDismiss`, never from `onChange`. SwiftUI drops a presentation that starts while another is still being dismissed.
3. **Picker:** `.photosPicker(isPresented:selection:matching: .images, preferredItemEncoding: .compatible)`.
4. **When an item arrives:**
   1. Load `loadTransferable(type: Data.self)`.
   2. Prepare it with `Task.detached { try PhotoPreparation.prepare(data) }.value`.
   3. Set `prepared`, which presents `.sheet(item: $prepared) { PhotoSendSheet(poet:photo:) }`.
   4. Reset the picker selection.
5. **If loading or preparing fails:** an alert titled `AccountAlert.title` with `OwnerCopy.photoSendFailed`. That is my call; the spec doesn't cover it.

- [ ] **Step 6: Run the tests, then try the flow**

Run `PhotoSendSheetTests` and `AccountAlertTests`, then the full suite. Expected: `** TEST SUCCEEDED **`.

On the simulator:
- **As an anonymous reader:** the button opens the sign-in sheet with both buttons. Close leaves things as they were. Settings' Account section looks as before.
- **If the owner signs in on the simulator:** the picker opens straight after. A picked photo shows in the send sheet's circle.
- **Send:** until the owner has created the bucket (Task 11), Send must show `photoSendFailed`. That checks the failure path. Do not send to production before the owner says so.

- [ ] **Step 7: Checkpoint.** `feat(ios): send a poet's photo`.

---

### Task 11: The privacy page, the full check and the release

**Files:**
- Modify: `firebase/hosting/privacy/index.html`

- [ ] **Step 1: Write the privacy page changes** (the owner reviews the wording before any deploy)
  - **A "Photos you send" item in the data list,** saying:
    - Photos are stored in Firebase Storage in the United States (us-central1) until the owner reviews them.
    - An approved photo is published on the poet's page and isn't linked to the sender. A rejected one is deleted.
    - Location and camera data are removed on the device before upload.
    - Deleting the account deletes photos still waiting, and approved ones stay.
    - A blocked account can't send photos.
  - **The two Frankfurt sentences (about lines 105 and 152):** these now say likes are in Frankfurt and photos waiting for review are in the United States.
- [ ] **Step 2: Look at the page**

  Run `npx -y firebase-tools@latest emulators:start --project demo-wuserade --only hosting` from `firebase/`. Open `http://localhost:5050/privacy` in the browser pane, read it, then stop the emulator.
- [ ] **Step 3: Run every suite.** Expected:
  - Swift: `** TEST SUCCEEDED **`.
  - Admin: no failures and no unexpected skips.
  - Rules: `# fail 0`.
- [ ] **Step 4: The owner's part.** Ask, and wait:
  1. Create the default Storage bucket in **us-central1**. The project must be on Blaze.
  2. Add Google's official G to the asset catalogue. It isn't in this plan's code.
  3. Write the new `[owner copy: …]` strings.
  4. Say go for the deploy.
- [ ] **Step 5: Deploy, after the go only**

  Run from `firebase/`:
  ```bash
  npx -y firebase-tools@latest deploy --project wuserade --only firestore:rules,storage,hosting
  ```
  Expected: `Deploy complete!`
- [ ] **Step 6: Try the whole flow on a device or simulator** (the spec's list)
  1. As an anonymous reader: tap the button, sign in with Apple, pick a photo, send it, and see the waiting line.
  2. `photos list`, then `photos approve <id>`: the photo appears and the button is gone.
  3. "Report this photo" opens Mail.
  4. Reject a second photo: the button comes back.
  5. `photos ban` a test account: sending is refused with `photoSendBanned`.
  6. Delete the account: `photos list` no longer shows its photos.
  7. Check night mode, AX text sizes and iPad.
- [ ] **Step 7: The release checklist, for the owner**
  - **App Privacy:** Photos or Videos, user content, linked to the user while waiting, used for app functionality.
  - **App Review notes:** photos are reviewed before publishing, "Report this photo" mails the owner, and `photos remove` and `photos ban` handle reports.
- [ ] **Step 8: Clean up.**
  - Run `rm -rf <scratchpad>/dd*` if any private build folder was made.
  - Stop the emulators.
  - Leave `~/Downloads/wuserade-photos/` to the owner.
