# Wuserade admin tool

Owner-only command line tool that fills and maintains the Firestore content of the Wuserade
app: `themes`, `authors`, `poems`, the search `catalog` chunks and `meta/content`. It also
reviews the photos of poets that readers send. It writes with the Firebase Admin SDK, so
Firestore and Storage security rules do not apply to it.

| Command | What it does |
|---|---|
| `migrate` | Copies themes, authors and poems from the old Postgres into Firestore, rebuilds, and checks the counts. |
| `rebuild` | Recomputes `poemsCount`, the `catalog` chunks and `meta/content` after edits made in the Firebase console. |
| `add-poem` | Adds one poem from a text file, then rebuilds. |
| `photos` | Lists, approves, rejects and removes the photos readers send of poets, and blocks senders. See [Poet photos](#poet-photos). |

## Setup

Needs Python 3.11 or newer.

```sh
cd firebase/admin
python3.11 -m venv .venv
.venv/bin/pip install -e '.[dev]'
```

## Credentials

The tool uses Application Default Credentials. No key file is needed, and none should ever
go into this repo.

```sh
gcloud auth application-default login
# If Firestore answers that it needs a quota project:
gcloud auth application-default set-quota-project wuserade
```

The Google account you log in with needs write access to Firestore in the `wuserade`
project (the project owner has it). The `photos` commands also write to Storage and set
claims on user accounts, which the project owner can do too.

Which database the tool talks to:

- **Normally** the Firestore database of project `wuserade`. This is the real, live data. The
  `photos` commands also use its Storage bucket and its user accounts.
- **If `FIRESTORE_EMULATOR_HOST` is set**, the local emulator (project `demo-wuserade`) and
  no credentials at all. Every command prints which one it is using as its first line.
- **The `photos` commands need three emulators**, not one: `FIRESTORE_EMULATOR_HOST`,
  `FIREBASE_AUTH_EMULATOR_HOST` and `STORAGE_EMULATOR_HOST` (or `FIREBASE_STORAGE_EMULATOR_HOST`)
  all set, or none of them. With only some set they stop with an error, because the part
  without an emulator would reach the real project.

## Postgres URL for `migrate`

Create `firebase/admin/.env` (it is git-ignored) with the *External* database URL from the
Render dashboard:

```
DATABASE_URL=postgresql://USER:PASSWORD@HOST/DBNAME
```

Or pass `--dsn URL` instead. Postgres is only read, never written. The tool never prints the
URL or its password: a URL that cannot be parsed gets a generic "not valid" message instead of
the text from the database driver (which would quote it), other connection errors have the URL
and password removed, and anything that looks like `user:password@` or `password=...` is
masked in error output, including when a URL is pasted without `--dsn`.

## Commands

Run them from `firebase/admin`:

### migrate

```sh
.venv/bin/python -m wuserade_admin migrate
.venv/bin/python -m wuserade_admin migrate --dsn 'postgresql://USER:PASSWORD@HOST/DBNAME'
```

Upserts every theme, author and poem by id (the Django ids are kept), copies each author's
name onto their poems, then runs a rebuild and prints the counts:

```
Postgres:  themes=14 authors=40 poems=4091
Firestore: themes=14 authors=40 poems=4091
Counts match.
```

The exit code is 1 if the counts differ. It is safe to run again, for example just before
release. Things to know:

- It replaces the documents of every id it reads, so edits made to migrated poems in the
  Firebase console are overwritten. Freeze edits on one side before the final run. Author
  documents are merged and a blank Django photo is not written, so an approved `photoURL`
  survives.
- It never deletes. Poems added with `add-poem` stay, and then Firestore holds more poems
  than Postgres, so the check reports a mismatch. That is expected once you start adding
  poems; the check matters for the first runs.

### rebuild

```sh
.venv/bin/python -m wuserade_admin rebuild
.venv/bin/python -m wuserade_admin rebuild --min-version 1.5
.venv/bin/python -m wuserade_admin rebuild --min-version ''
```

Run it after any manual edit in the Firebase console. It reads all content, recomputes
`poemsCount` on authors and themes, and refreshes the author name copied onto each poem
(`poems/{id}.authorName`) wherever it no longer matches `authors/{authorId}.name`, so renaming
an author in the console and running `rebuild` is enough (only the poems that differ are
written). It then writes `catalog/0..n-1` with a new `version` (previous `catalogVersion` + 1),
deletes catalog chunks that are no longer needed, and writes `meta/content` last, so the app
never sees a new `catalogVersion` before its chunks exist.

`--min-version` sets `meta/content.minimumAppVersion`, the app version below which the app
shows its "update the app" screen. Without the flag the current value is kept. `--min-version ''`
clears it. A value must look like `1.5` or `1.5.1`.

**Set the minimum version first, then change shapes.** Before publishing content that older app
versions cannot read (a new shape for the `catalog` chunks or for `meta/content`), run
`rebuild --min-version X`, where X is the first app version that reads the new shape, and only
then publish the new shape. The app reads `minimumAppVersion` before anything else in
`meta/content` and keeps it even when the rest fails to load, but setting it first means older
versions show the update screen before they ever meet content they cannot read. For the same
reason, never rename `minimumAppVersion` or store it as anything but a string: it is the one
field every app version must be able to read.

`nextPoemId` never goes down, even if you delete the newest poem, so a deleted id is not reused
(likes are stored by poem id).

Nothing is written if the check fails: a poem pointing at a missing author, a document missing
a required field, or a catalog chunk of 900,000 bytes or more (Firestore documents must stay
under 1 MiB; lower `CHUNK_SIZE` in `wuserade_admin/catalog.py` if that ever happens).

### add-poem

```sh
.venv/bin/python -m wuserade_admin add-poem \
  --title 'Poem title' --text-file poem.txt --author-id 12 --theme-id 3
```

`--theme-id` is optional. The text file must be UTF-8; leading and trailing blank space is
trimmed. The poem gets the id in `meta/content.nextPoemId`, which is advanced in the same
transaction, and the author and theme must already exist. Then the catalog is rebuilt, so
the new poem shows up in the app after its next catalog refresh.

## Poet photos

A reader who is signed in with Apple or Google can send a photo of a poet. It waits in
Storage at `photo-submissions/{authorId}/{uid}.jpg`, with a record
`photoSubmissions/{authorId}_{uid}`. That `{authorId}_{uid}` is the *submission ID*, for
example `12_Xk3v...`, and it is how the commands below name a photo. Nothing a reader sends is
public until you approve it.

```sh
.venv/bin/python -m wuserade_admin photos list [--out DIR]
.venv/bin/python -m wuserade_admin photos approve SUBMISSION_ID [--file PATH]
.venv/bin/python -m wuserade_admin photos reject SUBMISSION_ID
.venv/bin/python -m wuserade_admin photos remove AUTHOR_ID
.venv/bin/python -m wuserade_admin photos ban UID_OR_SUBMISSION_ID
.venv/bin/python -m wuserade_admin photos unban UID
```

- **`list`** downloads every waiting photo into `--out` (default `~/Downloads/wuserade-photos`)
  as `{authorId}-{poet name}-{first six characters of the uid}.jpg`, and prints one line per
  photo, oldest first (times are in your time zone), then the count:

  ```
  12_Xk3vP9qL2mT  Poet name  2026-10-28 14:05
  1 waiting photos in /Users/you/Downloads/wuserade-photos
  ```

  It shows everything that is waiting. A file whose record never arrived (the upload comes
  first) is listed with the age of the file; `approve` refuses it with "no waiting photo", so
  `reject` it. If the photo arrived only a moment ago its record may still follow, so run
  `list` again before you reject. A record whose file is gone is listed with `(no photo file)`;
  `reject` that too.
  Nothing is deleted, and a file already in the folder with the same name is overwritten.
- **`approve`** publishes the photo as the poet's photo and prints its URL. Look at the
  downloaded file first. To crop it, open the file in any image editor and pass the result with
  `--file`; the circle in the app shows the centre of the photo. Either way the photo is
  resized to at most 1,024 px on its long side and saved as a JPEG without EXIF data (so
  without a location). It sets `photoURL` on `authors/{id}` and on the poet's entry in
  `meta/content.authors` in one transaction, without a rebuild and without changing the
  catalog version, so apps do not download the catalog again. Then it deletes every waiting
  submission for that poet, records and files. A poet who already has a photo gets a new one
  with a new URL. The poet must be in `meta/content.authors` (only poets with poems are); if
  not, add poems and run `rebuild` first. When anything is wrong nothing is written. If
  `approve` fails after uploading, run it again: a failed transaction after the upload leaves
  the poet's stored URL with an old token until `approve` succeeds.
- **`reject`** deletes that waiting photo, its record and its file.
- **`remove`** takes a published photo down: it clears `photoURL` in both places and deletes
  `poets/{authorId}.jpg`.
- **`ban`** takes a uid, or a submission ID (the uid is the part after the `_`). It sets the
  `photoBan` claim on the sender's account and keeps their other claims, revokes their refresh
  tokens, and deletes their waiting photos, records and files. It prints how many it deleted.
  Firestore and Storage rules both refuse sends from a token with the claim, and they read it
  from the ID token the sender sends. Revoking does not cancel an ID token the sender already
  holds, so that token keeps working until it expires, within the hour. The ban applies from
  the sender's next token refresh. Photos you approved earlier stay up; take them down with
  `remove`.
- **`unban`** removes the claim and nothing else. A token minted while the ban was in place
  still carries the claim until its next refresh, so the sender can send again within the hour.

### When a reader reports a photo

"Report this photo" in the app opens a mail to you with the poet's name and ID.

A report about an approved photo is handled with `photos remove AUTHOR_ID`, which takes the
photo down. Approving deletes the submission, and nothing records who sent an approved photo
(the privacy page says it is not linked to the sender), so there is no sender to ban
afterwards.

Ban a sender at review time, while `photos list` still shows the submission ID:
`photos ban UID_OR_SUBMISSION_ID`, in place of `reject`, since it deletes their waiting photos
too. The part after the `_` is the sender's uid, which is also the account's User UID in the
Firebase console under Authentication.

## Tests

Pure tests (document builders, chunk size guard, Postgres row mapping, photo resizing) run anywhere:

```sh
.venv/bin/python -m pytest -q
```

The Firestore tests need the emulator and are skipped when `FIRESTORE_EMULATOR_HOST` is not
set. The photo tests also need the Storage and Auth emulators, and are skipped without them.
They only ever use project `demo-wuserade`. Run everything from `firebase/`:

```sh
cd firebase
npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore,storage,auth \
  "cd admin && .venv/bin/python -m pytest -q"
```

To try a command against the emulators by hand, start them in `firebase/`:

```sh
npx firebase-tools@latest emulators:start --project demo-wuserade --only firestore,storage,auth
```

Then, in `firebase/admin`, put the emulator variables in front of the command. `migrate`,
`rebuild` and `add-poem` need only the Firestore one:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 .venv/bin/python -m wuserade_admin rebuild
```

The `photos` commands need all three emulators, because they use Firestore, Storage and
Auth. With only some of the variables set they stop with an error instead of going to project
`wuserade`:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
STORAGE_EMULATOR_HOST=http://127.0.0.1:9199 \
.venv/bin/python -m wuserade_admin photos list
```
