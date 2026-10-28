# Wuserade admin tool

Owner-only command line tool that fills and maintains the Firestore content of the Wuserade
app: `themes`, `authors`, `poems`, the search `catalog` chunks and `meta/content`. It writes
with the Firebase Admin SDK, so Firestore security rules do not apply to it.

| Command | What it does |
|---|---|
| `migrate` | Copies themes, authors and poems from the old Postgres into Firestore, rebuilds, and checks the counts. |
| `rebuild` | Recomputes `poemsCount`, the `catalog` chunks and `meta/content` after edits made in the Firebase console. |
| `add-poem` | Adds one poem from a text file, then rebuilds. |

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
project (the project owner has it).

Which database the tool talks to:

- **Normally** the Firestore database of project `wuserade`. This is the real, live data.
- **If `FIRESTORE_EMULATOR_HOST` is set**, the local emulator (project `demo-wuserade`) and
  no credentials at all. Every command prints which one it is using as its first line.

## Postgres URL for `migrate`

Create `firebase/admin/.env` (it is git-ignored) with the *External* database URL from the
Render dashboard:

```
DATABASE_URL=postgresql://USER:PASSWORD@HOST/DBNAME
```

Or pass `--dsn URL` instead. Postgres is only read, never written. The URL is never printed.

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
  Firebase console are overwritten. Freeze edits on one side before the final run.
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
`poemsCount` on authors and themes, writes `catalog/0..n-1` with a new `version` (previous
`catalogVersion` + 1), deletes catalog chunks that are no longer needed, and writes
`meta/content` last, so the app never sees a new `catalogVersion` before its chunks exist.

`--min-version` sets `meta/content.minimumAppVersion`, the app version below which the app
shows its "update the app" screen. Without the flag the current value is kept. `--min-version ''`
clears it. A value must look like `1.5` or `1.5.1`.

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

## Tests

Pure tests (document builders, chunk size guard, Postgres row mapping) run anywhere:

```sh
.venv/bin/python -m pytest -q
```

The Firestore tests need the emulator and are skipped when `FIRESTORE_EMULATOR_HOST` is not
set. They only ever use project `demo-wuserade`. Run everything from `firebase/`:

```sh
cd firebase
npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore \
  "cd admin && .venv/bin/python -m pytest -q"
```

To try a command against the emulator by hand, start it with
`npx firebase-tools@latest emulators:start --project demo-wuserade --only firestore` in
`firebase/`, then run the command with `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` in front.
