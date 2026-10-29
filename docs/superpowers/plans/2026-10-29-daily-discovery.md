# Daily discovery: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wuserade stops feeling empty. Every day Home shows the day's poem, a poet of the day and a short poem, chosen on the server. A widget and an optional morning notification carry the day's poem outside the app. At the end of a poem the reader gets "more by this poet" and "you might also like", ranked by the server from their reading history.

**Architecture:** There are three parts.
- **Server:** the project's first Cloud Functions, in Python, in `firebase/functions/`. A pure package, `wuserade_daily`, holds the picking, ranking and scheduling rules. Three functions use it:
  - `writeDailyPicks` (scheduled daily) writes `daily/{date}` documents a week ahead;
  - `sendMorningPoems` (every 15 minutes) pushes the day's poem to readers whose time has come;
  - `keepReading` (callable) returns suggestions filtered by the caller's `users/{uid}/reads`.
- **Admin tool:** adds `lines` and `views` to the catalog. Its `rebuild` re-syncs the daily documents through `wuserade_daily`.
- **App:**
  - reads `daily/{date}` in place of the on-device `DailyRotation`;
  - records reads;
  - registers its device for the morning poem;
  - calls `keepReading`;
  - ships a WidgetKit extension that reads the same daily document over Firestore's REST API.

**Tech Stack:**
- SwiftUI with an iOS 17 target, WidgetKit and UserNotifications.
- Firebase iOS SDK (already a package), gaining the `FirebaseFunctions` product.
- Python 3.11+ with `firebase-functions` (2nd gen) and `firebase-admin`, tested with pytest.
- The Firestore emulator.
- `node:test` with `@firebase/rules-unit-testing`.

**Spec:** `docs/superpowers/specs/2026-10-29-daily-discovery-design.md` (approved 2026-10-29). Read it with this plan; the plan does not repeat its reasons. Mockups: `.superpowers/brainstorm/63457-1793273302/content/daily-first-version.html`.

## Global Constraints

- **iOS target:** iOS 17.0 for the app and the widget. Newer APIs go only behind `if #available`.
- **Swift files:** every new file starts with `// Minimum iOS 17.` and a short `//  ` summary, like the files around it. One type per file (nested types are fine). Tests use Swift Testing (`import Testing`, `@Test`), like `AccountManagerTests`.
- **Dependencies:** no new third-party packages. Add only the `FirebaseFunctions` product of the firebase-ios-sdk package already in the project. The widget links no Firebase product.
- **Folders:** the Xcode project syncs folders. Every new folder directly under `wuserade/`, and the new `WuseradeWidgets/` folder, needs a `PBXFileSystemSynchronizedRootGroup` entry in `project.pbxproj`. Subfolders of `Services/` need none.
- **Kabardian copy:** new strings are `[owner copy: …]` slots, spelled exactly as in this plan. Never write Kabardian. Any palochka is U+04C0. No emoji in text.
- **Design system:** colours from `Palette`, Alegreya only through `.serif(_:)`, spacing from `Space`. Reuse `SectionLabel`, `PoemRowLabel`, `NameRowLabel`, `PoemTitleBlock`, `VerseView`, `PoetPortrait`/`PoetInitials` and `Lozenge`.
- **No streaks, counters or badges** anywhere.
- **Region:** functions run in `europe-west3`, beside Firestore.
- **Reads:** the app never lists a content collection. The only lists it makes are of the user's own `reads` (in the account merge) and `likes`, as today.
- **Server data shapes, exactly:**
  - `daily/{YYYY-MM-DD}`: `date`, `poem`, `shortPoem`, `poet`, `createdAt`, as in the spec;
  - `users/{uid}/reads/{poemId}`: `poemId: Int`, `readAt: Timestamp`;
  - `users/{uid}/devices/{installId}`: `fcmToken`, `timeZone`, `notifyAt` (`"HH:MM"`), `enabled`, `nextSendAt`, `updatedAt`.
- **Production:** nothing is deployed to project `wuserade`, and nothing is committed or pushed, until the owner says so. Tests talk only to the emulators (project `demo-wuserade`). Leave the owner's uncommitted changes (`Palette.swift`, `Localizable.xcstrings`, `UpdateRequiredView.swift`, the deleted `accent.colorset`) exactly as they are.
- **Builds:** run `xcodebuild` without `-derivedDataPath`. Run `df -h /System/Volumes/Data` before the first build; below 20 GB free, stop and tell the owner.

**Commands used below.** Run each from the folder shown.

- **Swift tests, from the repository root:**
  ```bash
  xcodebuild test -project Wuserade.xcodeproj -scheme Wuserade -destination 'platform=iOS Simulator,id=C33052E2-0E82-4A95-B376-B6E33594C7C9' -only-testing:WuseradeTests/<Suite> 2>&1 | tail -n 5
  ```
  A pass ends with `** TEST SUCCEEDED **`. Leave out `-only-testing` to run everything.
- **Emulator port.** Port 8080 is taken on the owner's Mac, so the emulators run from a git-ignored `firebase/firebase.test.json`: a copy of `firebase.json` with `emulators.firestore.port` set to `8085`. Create it in Task 1 and add it to `.gitignore`.
- **Python tests, from `firebase/`.** `<dir>` is `admin` or `functions`:
  ```bash
  npx -y firebase-tools@latest emulators:exec --config firebase.test.json --project demo-wuserade --only firestore,storage,auth "cd <dir> && .venv/bin/python -m pytest -q"
  ```
  Unit tests alone: `cd firebase/<dir> && .venv/bin/python -m pytest -q -m "not emulator"`.
- **Rules tests, from `firebase/`:**
  ```bash
  npx -y firebase-tools@latest emulators:exec --config firebase.test.json --project demo-wuserade --only firestore,storage "npm --prefix rules-tests test"
  ```

## Review Focus

These five are the inputs a reader or the owner is most likely to hit that the main tests don't cover. Each has a test in the task named.

1. **Readers far from Frankfurt, near midnight.** A reader in UTC+14 or UTC−11 opens the app. Their local "today" must already have a daily document. Tested by `test_write_missing_days_covers_every_time_zone` (Task 3).
2. **First launch offline, or a cache left from yesterday.** Home must leave the daily sections out, never show yesterday's picks as today's, and never crash. Tested by `offlineWithoutCacheLeavesDailyOut` and `yesterdaysCacheIsNotToday` (Task 7).
3. **Signing out, signing in elsewhere, or deleting the account with the morning poem on.** The old account's device document must go, and a new one appears only if the toggle is on. Otherwise the phone gets two notifications, or one for an account that no longer exists. Tested by `signOutMovesTheDeviceToTheNewAccount` (Task 11) and `deleteAccountRemovesReadsAndDevice` (Task 9).
4. **A widget or notification for a poem that was since removed.** Tapping it must leave the reader where they are, not open a reader stuck on "retry". Tested by `linkToMissingPoemOpensNothing` (Task 12).
5. **Untitled poems.** Untitled poems appear in every pick and suggestion. The notification title and every row must use the first line. Tested by `test_untitled_message_uses_first_line` (Task 5) and `untitledDailyPoemUsesFirstLine` (Task 7).

---

### Task 1: Admin tool: line and view counts in the catalog

**Files:**
- Modify:
  - `firebase/admin/wuserade_admin/models.py` (`PoemRow`)
  - `firebase/admin/wuserade_admin/catalog.py` (`catalog_entries`, `poem_document`)
  - `firebase/admin/wuserade_admin/source.py` (`POEMS_SQL`, `poem_from_row`)
  - `firebase/admin/wuserade_admin/store.py` (`_read_content`)
  - `firebase/admin/wuserade_admin/__main__.py` (new `views` command)
  - `firebase/admin/README.md`
  - `.gitignore`
- Create:
  - `firebase/admin/wuserade_admin/views.py`
  - `firebase/firebase.test.json` (git-ignored)
- Test:
  - `firebase/admin/tests/test_catalog.py`
  - `firebase/admin/tests/test_views.py`
  - `firebase/admin/tests/test_store_emulator.py`

**Interfaces:**
- Produces:
  - `PoemRow.views: int = 0`, a new last field with a default.
  - `catalog.line_count(text: str) -> int`, the number of non-blank lines after splitting on `\r\n`, `\n` and `\r`.
  - Each catalog entry gains `"lines": int` and `"views": int`. `poem_document` gains `"views": int`.
  - `views.views_from_json(path: Path) -> dict[int, int]` reads Django's `data.json` dump.
  - `views.copy_views(db, views: dict[int, int]) -> int` updates only `poems/{id}.views` for poems that exist, in batches of 500, and returns the number written.
  - CLI: `python -m wuserade_admin views --dsn URL` or `views --json PATH`, then a rebuild.

- [ ] **Step 1: Write the failing tests**

```python
# test_catalog.py
def test_line_count_ignores_blank_lines_and_crlf():
    assert catalog.line_count("a\r\n\r\nb\nc\r") == 3
    assert catalog.line_count("") == 0

def test_catalog_entries_carry_lines_and_views():
    entry = catalog.catalog_entries([poem(id=1, text="a\nb", views=7)], {1: author(1)})[0]
    assert entry["lines"] == 2 and entry["views"] == 7

# test_views.py
def test_views_from_json_maps_pk_to_views(tmp_path):
    path = tmp_path / "data.json"
    path.write_text('[{"model":"poems.poem","pk":5,"fields":{"views":12}},{"model":"poems.author","pk":1,"fields":{}}]')
    assert views.views_from_json(path) == {5: 12}

# test_store_emulator.py
def test_copy_views_skips_unknown_poems_and_rebuild_reads_them(db): ...
    # upsert poems 1..3; copy_views(db, {1: 10, 2: 0, 99: 5}) == 2;
    # after rebuild, catalog entries for 1 and 3 have views 10 and 0, and poems/99 does not exist.
```

- [ ] **Step 2: Run the tests and confirm they fail.** Run the unit tests (`-m "not emulator"`), then the admin emulator command. Expected: FAIL, because `line_count`, `views` and the `views` field don't exist yet.
- [ ] **Step 3: Implement the changes.**
  - `POEMS_SQL` selects `views` as a new last column, and `poem_from_row` unpacks it.
  - `_read_content` reads `views` from each poem document, defaulting to 0.
  - `upsert_content` (used by `migrate`) writes `views` through `poem_document`.
  - The `views` command takes exactly one of `--dsn` or `--json`. With `--dsn` it reuses `read_postgres` and its secret masking, then calls `copy_views` and `rebuild`, and prints `views copied: N` before the rebuild output.
  - Create `firebase/firebase.test.json`, and add it to `.gitignore` along with `.superpowers/`.
- [ ] **Step 4: Run all the admin tests and confirm they pass.** Expected: every existing and new test passes.
- [ ] **Step 5: Update the README.** Document the `views` command in `firebase/admin/README.md`. Say that `--json` is the fallback when Render's Postgres is gone, and that poems missing from the dump keep 0.

### Task 2: The `wuserade_daily` package and the picking rules

**Files:**
- Create:
  - `firebase/functions/pyproject.toml` (package `wuserade_daily` only, Python ≥ 3.11, dev extra `pytest`)
  - `firebase/functions/requirements.txt` (`firebase-functions`, `firebase-admin`)
  - `firebase/functions/main.py` (empty entry module for now)
  - `firebase/functions/wuserade_daily/__init__.py`
  - `firebase/functions/wuserade_daily/text.py`
  - `firebase/functions/wuserade_daily/catalog.py`
  - `firebase/functions/wuserade_daily/picks.py`
  - `firebase/functions/tests/conftest.py`, the `db` fixture copied from the admin tool's, with the marker `emulator`
- Modify:
  - `firebase/firebase.json`: add `"functions": [{"source": "functions", "codebase": "default", "runtime": "python312"}]` (mirror it into `firebase.test.json`)
  - `.gitignore`: `firebase/functions/venv/`, `firebase/functions/.venv/`
  - `firebase/admin/README.md`: setup also runs `.venv/bin/pip install -e ../functions`
- Test:
  - `firebase/functions/tests/test_text.py`
  - `firebase/functions/tests/test_picks.py`

**Interfaces:**
- Produces, in `text.py`:
  - `normalize(s: str) -> str`: turns Latin `I`, `l`, `1` and `ӏ` (U+04CF) between Cyrillic letters into `Ӏ` (U+04C0), and trims the string.
  - `is_unknown_author(name: str) -> bool`: compares `normalize(name).casefold()` with that of `"Зытхар тщӀэкъым"`.
  - `sentence_case(title: str) -> str`: lower-cases the title, restores the palochka to U+04C0 and upper-cases the first letter.
  - `first_lines(text: str, n: int) -> list[str]`: the first `n` non-blank lines, stripped.
- Produces, in `catalog.py`:
  - `@dataclass(frozen=True) Entry(id: int, title: str, author_id: int, author_name: str, theme_id: int | None, lines: int, views: int, created_at: datetime)`
  - `@dataclass(frozen=True) Poet(id: int, name: str, poems_count: int, photo_url: str | None)`
  - `@dataclass(frozen=True) Catalog(version: int, entries: list[Entry], poets: list[Poet])`
  - `load_catalog(db) -> Catalog`, which reads `meta/content` and its `catalogChunks` chunks (missing `lines` or `views` read as 0)
- Produces, in `picks.py`:
  - `@dataclass(frozen=True) DayPicks(poem_id: int, short_poem_id: int, poet_id: int)`
  - `pick_day(day: date, catalog: Catalog, history: list[DayPicks]) -> DayPicks`. `history` lists earlier days, newest first, at most 365 of them.
  - `top_poems(catalog: Catalog, poet_id: int, n: int = 3) -> list[Entry]`: the `n` highest `views`, ties going to the newest `created_at`.

**The rules `pick_day` implements**, all randomness from `random.Random(day.isoformat())`, so a date always gives the same picks for the same inputs:
1. **The day's poem:** a random entry with `lines >= 2` whose id is not a `poem_id` in `history`. If every entry is used, take the least recently used one.
2. **The short poem:** a random entry with `2 <= lines <= 9`, other than the day's poem, whose id is not a `short_poem_id` in `history`. Prefer a different poet from the day's poem. When every short poem is used, take the least recently used one.
3. **The poet:** eligible poets have `poems_count >= 3` and are not `is_unknown_author`. The current cycle is the longest run of newest history days whose poets don't yet cover every eligible poet. The candidates are eligible poets not in that run. Prefer one who is not the poet of picks 1 and 2.

- [ ] **Step 1: Write the failing tests**

```python
def test_sentence_case_keeps_palochka():
    assert text.sentence_case("АНЭМ И ПСАЛЪЭ") == "Анэм и псалъэ"
    assert text.sentence_case("ПСЫ ЦӀЫКӀУ") == "Псы цӀыкӀу"

def test_unknown_author_matches_any_palochka_spelling():
    assert text.is_unknown_author("Зытхар тщIэкъым")

def test_pick_day_is_deterministic(): assert pick_day(D, CAT, []) == pick_day(D, CAT, [])
def test_day_poem_has_two_lines_and_is_not_repeated_within_history(): ...
def test_short_poem_is_2_to_9_lines_and_not_the_day_poem(): ...
def test_short_poems_fall_back_to_least_recently_used_when_exhausted(): ...
def test_every_eligible_poet_appears_once_before_any_repeats():
    # run 20 consecutive days over a catalog with 6 eligible poets, feeding each day's picks
    # into history: days 1-6 name 6 distinct poets, and so do days 7-12
def test_unknown_author_and_poets_under_three_poems_are_never_poet_of_the_day(): ...
def test_three_different_poets_when_possible(): ...
def test_untitled_poems_can_be_picked(): ...  # an entry with title "" is eligible
def test_top_poems_highest_views_then_newest(): ...
```

- [ ] **Step 2: Run the tests and confirm they fail.** `cd firebase/functions && python3.11 -m venv .venv && .venv/bin/pip install -e '.[dev]' -r requirements.txt && .venv/bin/python -m pytest -q -m "not emulator"`. Expected: FAIL with import errors.
- [ ] **Step 3: Implement `text.py`, `catalog.py` and `picks.py`** with the signatures and rules above.
- [ ] **Step 4: Run the tests and confirm they pass.** Then reinstall the admin venv with `-e ../functions` and run the admin unit tests, to show the shared package installs there too.

### Task 3: Daily documents: writing ahead, re-syncing, the scheduled function

**Files:**
- Create: `firebase/functions/wuserade_daily/daily.py`
- Modify:
  - `firebase/functions/main.py` (`writeDailyPicks`)
  - `firebase/admin/wuserade_admin/store.py` (`rebuild` calls `resync_days`)
  - `firebase/admin/wuserade_admin/__main__.py` (print `daily re-synced: N`)
- Test:
  - `firebase/functions/tests/test_daily_emulator.py`
  - `firebase/admin/tests/test_store_emulator.py`

**Interfaces:**
- Consumes: `Catalog`, `load_catalog`, `pick_day`, `top_poems` and `DayPicks` (Task 2).
- Produces, all in `daily.py`:
  - `daily_document(day: date, picks: DayPicks, catalog: Catalog, texts: dict[int, str]) -> dict`. It returns exactly the spec's shape:
    - `poem` and `shortPoem` are each `{id, title, authorId, authorName, text}`;
    - `poet` is `{id, name, poemsCount, topPoems: [{id, title}], photoURL?}`, with `photoURL` only when there is one;
    - plus `date` (`"YYYY-MM-DD"`) and `createdAt` (`SERVER_TIMESTAMP`).
  - `read_history(db, before: date, days: int = 365) -> list[DayPicks]`. It reads `daily` documents with IDs in `[before - days, before)`, newest first, in one range query on the document ID.
  - `write_missing_days(db, today: date, catalog: Catalog | None = None) -> list[str]`. Its range is `today - 1` through `today + 7` (`today` is the UTC date). It writes only dates with no document, in date order, so each day's history includes the days written before it. It fetches the two poem texts with `get_all`, and returns the dates it wrote.
  - `resync_days(db, today: date, catalog: Catalog) -> list[str]`. For every existing document from `today - 1` onward:
    - it refreshes the copied fields from current content;
    - it re-picks the poem, short poem or poet slot whose target no longer exists, with `pick_day`'s rules for that slot alone;
    - it writes only documents that changed, and returns their dates.
- In `main.py`, `writeDailyPicks` is `@scheduler_fn.on_schedule(schedule="10 0 * * *", timezone="UTC", region="europe-west3")` and calls `write_missing_days(firestore.client(), utc today)`.

- [ ] **Step 1: Write the failing tests**

```python
@pytest.mark.emulator
def test_write_missing_days_covers_every_time_zone(db):
    write_missing_days(db, date(2026, 10, 29))
    ids = {d.id for d in db.collection("daily").list_documents()}
    assert ids == {f"2026-10-{d}" for d in range(28, 32)} | {f"2026-11-0{d}" for d in range(1, 6)}

@pytest.mark.emulator
def test_write_missing_days_never_rewrites_a_written_day(db):
    # write once, change the stored poem id by hand, write again: the hand-changed value stays

@pytest.mark.emulator
def test_document_shape_matches_spec(db):
    doc = db.document("daily/2026-10-29").get().to_dict()
    assert set(doc) == {"date", "poem", "shortPoem", "poet", "createdAt"}
    assert set(doc["poem"]) == {"id", "title", "authorId", "authorName", "text"}
    assert len(doc["poet"]["topPoems"]) == 3

@pytest.mark.emulator
def test_resync_refreshes_corrected_text_from_yesterday_on_only(db): ...
@pytest.mark.emulator
def test_resync_repicks_a_removed_poem_and_a_removed_poet(db): ...

# admin test_store_emulator.py
def test_rebuild_resyncs_daily_documents(db): ...  # edit a picked poem's text, rebuild, daily doc shows the new text
```

- [ ] **Step 2: Run the tests and confirm they fail** (functions and admin emulator suites). Expected: FAIL, because `daily` doesn't exist.
- [ ] **Step 3: Implement `daily.py` and `writeDailyPicks`.** Then make `rebuild` call `resync_days` after it writes `meta/content`, add `daily_resynced: int` to `RebuildResult`, and print it.
- [ ] **Step 4: Run both emulator suites and confirm everything passes.**

### Task 4: Keep reading: the ranking and the callable function

**Files:**
- Create: `firebase/functions/wuserade_daily/keep_reading.py`
- Modify: `firebase/functions/main.py` (`keepReading`)
- Test:
  - `firebase/functions/tests/test_keep_reading.py` (unit)
  - `firebase/functions/tests/test_keep_reading_emulator.py`

**Interfaces:**
- Consumes: `Catalog`, `Entry` and `load_catalog` (Task 2).
- Produces, in `keep_reading.py`:
  - `@dataclass(frozen=True) Candidates(poet: list[int], theme: list[int], liked: list[int], length: list[int])`
  - `rank(poem_id: int, catalog: Catalog, liked_author_ids: set[int]) -> Candidates`. It builds these lists:
    - `poet`: the poem's poet's other poems by `views`, highest first, at most 10;
    - `theme`: same-theme poems by other poets, most-read first, at most 5. Empty when the poem has no theme;
    - `liked`: poems by liked poets other than this poet, most-read first, at most 5;
    - `length`: other poets' poems with `abs(lines - poem.lines) <= 3`, most-read first, at most 5.

    No id appears in two lists, and the poem itself appears in none.
  - `choose(c: Candidates, read_ids: set[int]) -> tuple[list[int], list[int]]`. It returns the first 3 unread of `poet`, then up to 2 unread filled from `theme`, `liked` and `length`, in that order. The spec says "first match wins"; filling across the lists in that order keeps the same priority but shows two rows more often.
  - `keep_reading(db, uid: str, poem_id: int, catalog: Catalog) -> dict`, which returns `{"poet": [{"id", "title"}], "similar": [{"id", "title", "authorId", "authorName"}]}`. It reads the caller's 20 newest likes, ordered by `likedAt` descending, only when `theme` has fewer than 5 candidates. Then it checks every candidate id against `users/{uid}/reads/{id}` in one `get_all`, at most 25 documents.
- In `main.py`: `keepReading` is `@https_fn.on_call(region="europe-west3")`.
  - It requires `req.auth`, or raises `UNAUTHENTICATED`.
  - `poemId` must be an int that exists, or it raises `INVALID_ARGUMENT`.
  - It keeps a module-level `Catalog`, re-loaded when `meta/content.catalogVersion` differs: one `meta` read per call, and the chunks only on a change.

- [ ] **Step 1: Write the failing tests**

```python
def test_poet_list_is_most_read_first_and_skips_read(): assert choose(rank(...), {11})[0] == [12, 13, 14]
def test_similar_fills_from_theme_then_liked_then_length(): ...
def test_no_id_in_both_lists_and_never_the_poem_itself(): ...
def test_poem_without_theme_uses_liked_then_length(): ...
@pytest.mark.emulator
def test_keep_reading_filters_by_the_callers_reads_only(db):
    # reads under users/u1 hide poems for u1, not for u2
@pytest.mark.emulator
def test_keep_reading_reads_at_most_25_read_documents(db, monkeypatch): ...  # count get_all ids
```

- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement `keep_reading.py` and `keepReading`.**
- [ ] **Step 4: Run the unit and emulator tests and confirm they pass.**

### Task 5: The morning push: schedule, message, sending

**Files:**
- Create: `firebase/functions/wuserade_daily/morning.py`
- Modify: `firebase/functions/main.py` (`sendMorningPoems`)
- Test:
  - `firebase/functions/tests/test_morning.py`
  - `firebase/functions/tests/test_morning_emulator.py`

**Interfaces:**
- Consumes: the `daily/{date}` shape (Task 3), and `sentence_case` and `first_lines` (Task 2).
- Produces, in `morning.py`:
  - `next_send_at(time_zone: str, notify_at: str, after: datetime) -> datetime` returns the first UTC instant strictly after `after` whose local time in `time_zone` is `notify_at`. A local time skipped by a daylight-saving change moves forward by the gap. A repeated local time uses its first occurrence.
  - `message(token: str, daily: dict) -> messaging.Message` builds the message:
    - the title is `f"{sentence_case(title)} — {authorName}"`, or with the first line in place of the title for an untitled poem;
    - the body is `"\n".join(first_lines(text, 2))`;
    - `data` is `{"poemId": str(id), "date": daily["date"]}`;
    - the APNs payload has no sound.
  - `send_due(db, now: datetime, send: Callable[[list[messaging.Message]], messaging.BatchResponse]) -> int` runs a collection-group query on `devices` with `enabled == True` and `nextSendAt <= now`, in pages of 500.
    - For each device it loads `daily/{its local date}`, caching each date for the run.
    - It sends in batches of 500.
    - It deletes devices whose send failed with `UnregisteredError` or `SenderIdMismatchError`.
    - For every device it sent to, it sets `nextSendAt = next_send_at(...)` and `updatedAt`.
    - A device whose daily document is missing is skipped: its `nextSendAt` advances and nothing is sent.
    - It returns the number sent.
- In `main.py`, `sendMorningPoems` is `@scheduler_fn.on_schedule(schedule="*/15 * * * *", region="europe-west3")` and calls `send_due(..., messaging.send_each)`.

- [ ] **Step 1: Write the failing tests**

```python
def test_next_send_at_same_day_and_next_day():
    after = datetime(2026, 10, 29, 4, 0, tzinfo=UTC)          # 07:00 in Moscow
    assert next_send_at("Europe/Moscow", "08:00", after) == datetime(2026, 10, 29, 5, 0, tzinfo=UTC)
    assert next_send_at("Europe/Moscow", "08:00", datetime(2026, 10, 29, 5, 0, tzinfo=UTC)) == datetime(2026, 10, 30, 5, 0, tzinfo=UTC)
def test_next_send_at_skipped_hour_moves_forward():     # Europe/Berlin, 2027-03-28 "02:30" -> 01:30 UTC
def test_next_send_at_repeated_hour_uses_first():        # Europe/Berlin, 2026-10-25 "02:30" -> 00:30 UTC
def test_next_send_at_far_zones(): ...                   # Pacific/Kiritimati and Pacific/Pago_Pago
def test_untitled_message_uses_first_line():
    m = message("t", {"date": "2026-10-29", "poem": {"id": 7, "title": "", "authorName": "А", "text": "Line one,\nLine two\nLine three"}})
    assert m.notification.title == "Line one, — А" and m.notification.body == "Line one,\nLine two"
@pytest.mark.emulator
def test_send_due_sends_once_and_advances(db): ...       # a second run at the same `now` sends nothing
@pytest.mark.emulator
def test_send_due_deletes_unregistered_tokens(db): ...
@pytest.mark.emulator
def test_send_due_uses_the_devices_local_date(db): ...   # Pacific/Kiritimati gets tomorrow's UTC date
```

- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement `morning.py` and `sendMorningPoems`** (with `zoneinfo`).
- [ ] **Step 4: Run the tests and confirm they pass.**

### Task 6: Security rules and the devices index

**Files:**
- Modify:
  - `firebase/firestore.rules`
  - `firebase/firestore.indexes.json` (collection-group index on `devices`: `enabled` ASC, `nextSendAt` ASC)
- Test: `firebase/rules-tests/rules.test.mjs`

**Interfaces:**
- Produces the rules:
  - `match /daily/{date} { allow get: if true; }`
  - inside `match /users/{uid}`:
    - `reads/{readId}`: the owner may read and delete; the owner may create with `validRead(readId)`; nothing else.
    - `devices/{installId}`: the owner may read and delete; the owner may create and update with `validDevice(installId)`.
- `validRead(readId)`: the keys are exactly `poemId` and `readAt`; `poemId is int`; `poemId == int(readId)`; `readAt == request.time`.
- `validDevice(installId)`:
  - the keys are exactly the six device fields;
  - `fcmToken is string && fcmToken.size() <= 4096`;
  - `timeZone is string && timeZone.size() <= 64`;
  - `notifyAt.matches('^([01][0-9]|2[0-3]):[0-5][0-9]$')`;
  - `enabled is bool`;
  - `nextSendAt is timestamp`;
  - `updatedAt == request.time`;
  - `installId.size() <= 64`.

- [ ] **Step 1: Write the failing tests:**
  - `daily` documents can be read by anyone but never listed or written;
  - a reader can create their own read with `serverTimestamp()` but not another user's;
  - a read with any other field is refused;
  - a read with a client-supplied `readAt` is refused;
  - updating a read is refused;
  - the owner can list and delete their own reads;
  - a device with a bad `notifyAt` (`"8:00"`, `"24:00"`) or an extra field is refused;
  - a device can't be written under another uid;
  - the owner can update and delete their own device.
- [ ] **Step 2: Run the rules tests and confirm they fail.**
- [ ] **Step 3: Implement the rules and the index.**
- [ ] **Step 4: Run the rules tests and confirm they pass,** including every existing test.

### Task 7: App: the daily document and Library

**Files:**
- Create a new synced folder, `wuserade/Shared/`, that belongs to the app and the widget. It holds:
  - `DailyPicks.swift`
  - `DailyDate.swift`
  - `DailyCache.swift`
  - `FirestoreREST.swift`
- Create: `wuserade/Services/Daily/DailyStore.swift`
- Modify:
  - `wuserade/Catalog/Library.swift`
  - `wuserade/wuseradeApp.swift`
  - `wuserade/Preview Content/PreviewContent.swift`
  - `wuserade/Wuserade.entitlements` (App Group `group.com.nart.wuserade`)
  - `project.pbxproj` (the `Shared` root group)
- Delete:
  - `wuserade/Home/DailyRotation.swift`
  - `wuserade/Home/DaysPoemSource.swift`
- Test:
  - `wuseradeTests/DailyPicksTests.swift`
  - `wuseradeTests/LibraryDailyTests.swift`
  - `wuseradeTests/Fakes.swift` (`FakeDailyStore`)
  - fix existing tests that passed a `daysSource`

**Interfaces:**
- Produces, in `wuserade/Shared/`:
  - `struct DailyPoem: Codable, Hashable { id: Int; title: String; authorId: Int; authorName: String; text: String; var poem: Poem; var summary: PoemSummary }`. `summary` uses `PoemSummary(poem)`, so an untitled poem lists by its first line.
  - `struct DailyPoemRef: Codable, Hashable { id: Int; title: String }`
  - `struct DailyPoet: Codable, Hashable { id: Int; name: String; poemsCount: Int; photoURL: String?; topPoems: [DailyPoemRef]; var author: Author }`
  - `struct DailyPicks: Codable, Hashable { date: String; poem: DailyPoem; shortPoem: DailyPoem; poet: DailyPoet }`. `createdAt` is ignored.
  - `enum DailyDate { static func string(for date: Date, in timeZone: TimeZone = .current) -> String }` returns a Gregorian, POSIX `yyyy-MM-dd` date.
  - `struct DailyCache { init(directory: URL?); static let shared: DailyCache; func load() -> DailyPicks?; func save(_ picks: DailyPicks) }`:
    - `shared` uses the App Group container (`group.com.nart.wuserade`), with file `daily.json`;
    - `save` also calls `WidgetCenter.shared.reloadAllTimelines()` when the stored date changes.
  - `enum FirestoreREST { static func decode<T: Decodable>(_ type: T.Type, from documentJSON: Data) throws -> T }` unwraps Firestore REST values (`stringValue`, `integerValue` as a string, `booleanValue`, `nullValue`, `timestampValue`, `mapValue.fields`, `arrayValue.values`) into plain JSON, then decodes it.
- Produces, in `wuserade/Services/Daily/`:
  - `protocol DailyStore: Sendable { func fetch(date: String) async throws -> DailyPicks? }`
  - `struct FirestoreDailyStore: DailyStore`, which reads `daily/{date}` and returns nil when the document is missing.
- Produces, in `Library`:
  - `init(store: CatalogStore, dailyStore: any DailyStore = FirestoreDailyStore(), dailyCache: DailyCache = .shared)`
  - `private(set) var daily: DailyPicks?`
  - `var daysPoem: Poem?`, now computed: `daily?.poem.poem`
  - `func loadDaily(now: Date = .now) async`, which replaces `loadDaysPoem`. Its order:
    1. Use a cache whose `date` is today.
    2. Otherwise fetch today's document. On success, save it to the cache and remember both poems.
    3. On failure or a missing document, set `daily` to nil unless the cache holds today.

    `loadHome` and `refreshHome` call it, and a refresh always fetches.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func `Decodes the server document`() throws   // Firestore-shaped dictionary fixture, photoURL absent
@Test func `Decodes the REST document`() throws     // fixture with integerValue "4130", mapValue, arrayValue
@Test func `untitledDailyPoemUsesFirstLine`()        // DailyPoem(title: "", text: "Line one,\nLine two").summary.firstLine == "Line one"
@Test func `DailyDate uses the local calendar day`()  // 2026-10-29T22:30Z is "2026-10-30" in Europe/Moscow
@Test func `todaysCacheIsUsedWithoutFetching`() async
@Test func `fetchedDailyIsCachedAndPoemsRemembered`() async
@Test func `offlineWithoutCacheLeavesDailyOut`() async     // store throws, empty cache: daily == nil, no crash
@Test func `yesterdaysCacheIsNotToday`() async             // cache date 2026-10-28, store throws, now 2026-10-29: daily == nil
@Test func `refreshFetchesEvenWithTodaysCache`() async
```

- [ ] **Step 2: Run `DailyPicksTests` and `LibraryDailyTests` and confirm they fail** to compile.
- [ ] **Step 3: Implement it.** Add the App Group to the app's entitlements, and the `Shared` group to the project. Delete `DailyRotation` and `DaysPoemSource`, along with their UserDefaults keys (`daysPoem.day` and `daysPoem.poem`, removed once at launch). Point previews at a `FakeDailyStore` fixture.
- [ ] **Step 4: Run every Swift test and confirm they pass.**

### Task 8: App: Home's poet of the day and short poem

**Files:**
- Create:
  - `wuserade/Home/PoetOfTheDaySection.swift`
  - `wuserade/Home/ShortPoemSection.swift`
- Modify:
  - `wuserade/Home/HomeView.swift`
  - `wuserade/Home/NewColumn.swift`
  - `wuserade/Text/OwnerCopy.swift`
  - `wuserade/Managers/AnalyticsManager.swift` (typed helper)

**Interfaces:**
- Consumes: `Library.daily`, `DailyPoet`, `DailyPoem` and `DailyPoemRef` (Task 7).
- Produces:
  - `PoetOfTheDaySection(poet: DailyPoet)`, which shows:
    - a head `SectionLabel(text: OwnerCopy.poetOfTheDay)`;
    - `PoetPortrait`, or `PoetInitials` when `photoURL` is nil;
    - the name and `"\(poemsCount) \(OwnerCopy.countNoun)"`;
    - three title rows, each opening `.reader(ReaderContext(poems: three summaries, index: i))`;
    - `OwnerCopy.allTheirPoems ›`, which opens `.poet(poet.author)`, as do the name and portrait.
  - `ShortPoemSection(poem: DailyPoem)` shows `SectionLabel(text: OwnerCopy.shortPoem)`, a `PoemTitleBlock` (the title opens the reader with `ReaderContext(single:)`, the poet opens `.poet`) and the full `VerseView`.
  - New `OwnerCopy` slots: `poetOfTheDay = "[owner copy: poet of the day]"`, `shortPoem = "[owner copy: a short poem]"`, `allTheirPoems = "[owner copy: all their poems]"`.
  - `AnalyticsManager.dailyOpen(source: String)` logs `daily_open`, with `source` one of `home_poem`, `home_poet`, `home_short`, `widget` or `notification`.
- `HomeView` order: the day's page, the poet section, the short-poem section, then the new poems and themes as today.
- `NewColumn`, under the day's poem row, adds:
  - the short poem as a `PoemRowLabel` row under `SectionLabel(text: OwnerCopy.shortPoem)`;
  - the poet as a `NameRowLabel` row under `SectionLabel(text: OwnerCopy.poetOfTheDay)` that pushes `.poet`.

- [ ] **Step 1: Build the views** and wire them into `HomeView` and `NewColumn`, using `FakeDailyStore` previews with an untitled short poem and a poet without a photo.
- [ ] **Step 2: Build the app, then run every Swift test.** The build must succeed and the tests pass.
- [ ] **Step 3: Check it on the simulator.**
  - Run the app with the preview fixture, and check Home in compact width against the mockup (screen 1).
  - Check it at the largest accessibility text size and in night mode.
  - Check the iPad split view.
  - Save screenshots to the scratchpad.

### Task 9: App: reading history and the account

**Files:**
- Create:
  - `wuserade/Services/Reads/ReadsStore.swift`
  - `wuserade/Services/Reads/PendingReadsStore.swift`
  - `wuserade/Services/Reads/ReadsController.swift`
  - `wuserade/Services/Reads/ReadTracker.swift`
- Modify:
  - `wuserade/Services/Account/AccountManager.swift`
  - `wuserade/wuseradeApp.swift`
  - `wuserade/Reader/ReaderPage.swift`
  - `wuserade/Reader/ReaderPager.swift`
- Test:
  - `wuseradeTests/ReadTrackerTests.swift`
  - `wuseradeTests/ReadsControllerTests.swift`
  - `wuseradeTests/AccountManagerTests.swift`
  - `wuseradeTests/Fakes.swift` (`FakeReadsStore`)

**Interfaces:**
- Produces:
  - The store:
    - `protocol ReadsStore: Sendable`, with these members:
      - `func markRead(poemId: Int, uid: String) async throws`
      - `func fetchReadIDs(uid: String) async throws -> [Int]`: server-confirmed, listing the user's own reads
      - `func deleteAllReads(uid: String) async throws`
    - `FirestoreReadsStore` writes `{poemId, readAt: FieldValue.serverTimestamp()}`.
  - `PendingReadsStore` (UserDefaults, like `PendingLikesStore`) has `load() -> Set<Int>`, `save(_:)` and `clear()`.
  - `@MainActor @Observable final class ReadsController`:
    - `init(store: any ReadsStore, defaults: UserDefaults = .standard)`
    - `func bind(uid: String?)`
    - `func markRead(_ poemId: Int)`

    It keeps the IDs already written per uid in UserDefaults (`reads.known.<uid>`) and writes each poem once. It logs write errors and drops them; a permission-denied answer means the read already exists.
  - `@MainActor final class ReadTracker`:
    - `init(minimumShown: Duration = .seconds(10), minimumAtEnd: Duration = .seconds(3), clock: any Clock<Duration> = ContinuousClock(), onRead: @escaping (Int) -> Void)`
    - `func shown(_ poemId: Int)`, `func hidden(_ poemId: Int)` and `func reachedEnd(_ poemId: Int)`

    A poem counts as read once it has been shown continuously for `minimumShown`, or has reached the end after being shown for at least `minimumAtEnd`. `onRead` fires once per poem per tracker.
  - `AccountManager.init` gains `reads: any ReadsStore` and `pendingReads: PendingReadsStore`:
    - `performDeleteAccount` calls `reads.deleteAllReads(uid:)` before `likes.deleteAllData(uid:)`;
    - `switchToExistingAccount` saves `fetchReadIDs(anonymous)` into `pendingReads` next to the likes, and deletes the anonymous reads in its cleanup;
    - `adopt` uploads `pendingReads` with one `markRead` per ID, ignoring errors, then clears it.
- In the reader: `ReaderPage` calls `tracker.shown` and `tracker.hidden` when its page becomes current or stops being current in `ReaderPager`, and `tracker.reachedEnd` when the closing `Lozenge` appears on screen. The app owns one `ReadTracker` whose `onRead` calls `readsController.markRead`, and passes it through the environment. `ReadsController.bind` follows the account's uid.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func `Ten seconds shown counts once`() async         // TestClock advance 10s -> onRead([7]); advance again -> still once
@Test func `pagingPastWithinThreeSecondsDoesNotCount`() async // shown, reachedEnd at 1s, hidden at 2s -> no read
@Test func `End after three seconds counts`() async
@Test func `Hiding resets the shown time`() async
@Test func `Each poem is written once per account`() async    // ReadsController
@Test func `deleteAccountRemovesReadsAndDevice`() async     // CallLog order: deleteAllReads before deleteAllData (device in Task 11)
@Test func `Switching to an existing account carries anonymous reads`() async
```

  (`TestClock` is a small manual clock in `Fakes.swift`.)
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement it,** updating `AccountManagerTests`' `Env` with the new fakes.
- [ ] **Step 4: Run every Swift test and confirm they pass.**

### Task 10: App: keep reading in the reader

**Files:**
- Create:
  - `wuserade/Services/KeepReading/KeepReadingService.swift`
  - `wuserade/Services/KeepReading/KeepReading.swift`
  - `wuserade/Reader/KeepReadingSection.swift`
- Modify:
  - `wuserade/Reader/ReaderPage.swift`
  - `wuserade/Text/OwnerCopy.swift`
  - the Xcode project: add the `FirebaseFunctions` product to the app target
- Test:
  - `wuseradeTests/KeepReadingTests.swift`
  - `wuseradeTests/Fakes.swift` (`FakeKeepReadingService`)

**Interfaces:**
- Produces:
  - `struct KeepReading: Decodable, Equatable { poet: [Ref]; similar: [Similar] }`, where `Ref` is `{id, title}` and `Similar` is `{id, title, authorId, authorName}`. It has two helpers:
    - `func poetSummaries(author: Author) -> [PoemSummary]`
    - `var similarSummaries: [PoemSummary]`

    Both give `themeId: nil` and `createdAt: .distantPast`.
  - `protocol KeepReadingService: Sendable { func suggestions(for poemId: Int) async throws -> KeepReading }`
  - `FirebaseKeepReadingService` calls `Functions.functions(region: "europe-west3").httpsCallable("keepReading")` with `["poemId": poemId]`.
  - `KeepReadingSection(suggestions: KeepReading, author: Author)` shows the following, leaving out an empty section:
    - `SectionLabel(text: "\(OwnerCopy.moreBy) \(author.name)")`, then the poet rows;
    - `SectionLabel(text: OwnerCopy.youMightAlsoLike)`, then the similar rows.

    Each row opens `.reader(ReaderContext(poems: thatSection, index: i))`, and logs `keep_reading_open` with `section` `poet` or `similar`.
  - `OwnerCopy`: `moreBy = "[owner copy: more by]"`, `youMightAlsoLike = "[owner copy: you might also like]"`.
- `ReaderPage.loaded` loads suggestions in `.task(id: summary.id)`.
  - Until they arrive, or when they fail or come back empty, it shows today's `NextPoemRow` if there is a `next`.
  - Once they arrive, `KeepReadingSection` replaces `NextPoemRow`. The suggestions fade in below the lozenge, without moving the verse.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func `Decodes the callable result`() throws
@Test func `Poet rows carry the reader's poet`()
@Test func `Empty result keeps the next row`()   // a small `KeepReadingState.resolve(result:next:)` decides what shows
@Test func `Failure keeps the next row`()
```

- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement it.** Put the show-what decision in `KeepReadingState` (in `KeepReading.swift`), so it can be tested without views.
- [ ] **Step 4: Run every Swift test, and check the end of a poem on the simulator** with the fake service against mockup screen 4.

### Task 11: App: the morning poem setting and device registration

**Files:**
- Create:
  - `wuserade/Services/Morning/DeviceRegistry.swift`
  - `wuserade/Services/Morning/MorningSchedule.swift`
  - `wuserade/Services/Morning/MorningPoemController.swift`
  - `wuserade/Services/Morning/NotificationPermission.swift`
  - `wuserade/Services/Morning/InstallID.swift`
  - `wuserade/Settings/MorningPoemSection.swift`
- Modify:
  - `wuserade/wuseradeApp.swift` (`AppDelegate` passes the FCM token on)
  - `wuserade/Settings/SettingsSheet.swift`
  - `wuserade/Services/Account/AccountManager.swift`
  - `wuserade/Text/OwnerCopy.swift`
  - delete `wuserade/Managers/NotificationManager.swift` if nothing uses it
- Test:
  - `wuseradeTests/MorningScheduleTests.swift`
  - `wuseradeTests/MorningPoemControllerTests.swift`
  - `wuseradeTests/AccountManagerTests.swift`
  - `wuseradeTests/Fakes.swift`

**Interfaces:**
- Produces:
  - `enum MorningSchedule { static func nextSendAt(timeZone: TimeZone, notifyAt: String, after: Date) -> Date }`, with the same rule as the server's `next_send_at` (Task 5).
  - `struct DeviceRegistration: Equatable { fcmToken: String; timeZone: String; notifyAt: String; enabled: Bool; nextSendAt: Date }`
  - `protocol DeviceRegistry: Sendable`:
    - `func upsert(_ device: DeviceRegistration, installId: String, uid: String) async throws`: `updatedAt` is the server timestamp
    - `func remove(installId: String, uid: String) async throws`
  - `FirestoreDeviceRegistry` writes `users/{uid}/devices/{installId}`.
  - `enum InstallID { static func current(defaults: UserDefaults = .standard) -> String }` returns a random UUID string, created once and stored.
  - `protocol NotificationPermission: Sendable { func status() async -> UNAuthorizationStatus; func request() async -> Bool }`
  - `@MainActor @Observable final class MorningPoemController` stores `enabled` and `notifyAt` (default `"08:00"`) in UserDefaults:
    - `init(registry: any DeviceRegistry, permission: any NotificationPermission, installId: String, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init)`
    - `private(set) var enabled: Bool`
    - `private(set) var notifyAt: String`
    - `private(set) var permissionDenied: Bool`
    - `func setEnabled(_ on: Bool) async`: turning it on requests permission. If permission is refused, `enabled` stays false and `permissionDenied` becomes true.
    - `func setTime(_ hhmm: String) async`
    - `func tokenChanged(_ token: String?) async`
    - `func accountChanged(uid: String?) async`
    - `func timeZoneChanged() async`

    It upserts whenever the uid, token, time, time zone or `enabled` changes and there is a uid and a token. Turning it off upserts `enabled: false`.
  - `AccountManager.init` gains `devices: any DeviceRegistry` and `installId: String`. It calls `devices.remove(installId:uid:)`:
    - in `performSignOut`, before `signOut`, logging any error;
    - in `performDeleteAccount`, after the reads and before `likes.deleteAllData`, throwing on error;
    - in `switchToExistingAccount`'s anonymous cleanup, logging any error.
  - `MorningPoemSection` is the Settings section: a `Toggle(OwnerCopy.morningPoem)` and a `DatePicker(OwnerCopy.morningPoemTime, displayedComponents: .hourAndMinute)` shown while it is on. While `permissionDenied`, it adds `OwnerCopy.notificationsOff` and a button `OwnerCopy.openSettings` that opens `UIApplication.openSettingsURLString`. It logs `morning_poem` with `enabled`.
  - `OwnerCopy`:
    - `morningPoem = "[owner copy: morning poem]"`
    - `morningPoemTime = "[owner copy: time]"`
    - `notificationsOff = "[owner copy: notifications are off for Wuserade in iOS Settings]"`
    - `openSettings = "[owner copy: open Settings]"`
- `AppDelegate.messaging(_:didReceiveRegistrationToken:)` forwards the token, through a `NotificationCenter` post the app observes, to `tokenChanged`. Replace the `print`. The app also calls `timeZoneChanged()` on `NSSystemTimeZoneDidChange` and on becoming active.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func `nextSendAt matches the server rule`()        // same Moscow and Berlin cases as Task 5
@Test func `Turning on asks permission and registers`() async
@Test func `Refused permission keeps it off`() async
@Test func `Changing the time re-registers with a new nextSendAt`() async
@Test func `No uid or no token registers nothing`() async
@Test func `signOutMovesTheDeviceToTheNewAccount`() async // AccountManager removes under the old uid; controller upserts under the new one
@Test func `deleteAccountRemovesReadsAndDevice`() async    // extend Task 9's test: remove(installId, uid) before deleteAllData
```

- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run every Swift test, then check Settings on the simulator** against the mockup (screen 3, Settings rows).

### Task 12: App: the invitation, and opening a poem from a link or notification

**Files:**
- Create:
  - `wuserade/Shared/DeepLink.swift`
  - `wuserade/Shell/PoemLinkOpener.swift`
  - `wuserade/Home/MorningInvitationCard.swift`
  - `wuserade/Services/Morning/VisitDays.swift`
- Modify:
  - `wuserade/Shell/RootView.swift` (`onOpenURL` for poem links, and switching to the first tab)
  - `wuserade/wuseradeApp.swift` (`userNotificationCenter(_:didReceive:)`, and the Google handler stays)
  - `wuserade/Home/HomeView.swift`
  - `wuserade/Text/OwnerCopy.swift`
- Test:
  - `wuseradeTests/DeepLinkTests.swift`
  - `wuseradeTests/MorningInvitationTests.swift`

**Interfaces:**
- Produces:
  - `enum DeepLink`:
    - `static func poemURL(_ id: Int, source: String) -> URL` builds `wuserade://poem/{id}?source=widget|notification`;
    - `static func poem(from url: URL) -> (id: Int, source: String?)?`
  - `struct VisitDays`:
    - `init(defaults: UserDefaults = .standard)`
    - `mutating func record(_ date: Date)`: keeps at most 3 distinct `DailyDate` strings
    - `var count: Int`
    - `var invitationDone: Bool { get set }`
  - `enum MorningInvitation { static func shouldShow(visitDays: Int, done: Bool, enabled: Bool) -> Bool }` is true only when `visitDays >= 3 && !done && !enabled`.
  - `MorningInvitationCard`, shown on Home under the day's page while `shouldShow` is true, holds:
    - text: `OwnerCopy.morningInvitation`;
    - a `.primaryCapsule` button, `OwnerCopy.turnOn`, which calls `setEnabled(true)` and sets done;
    - a `.secondaryCapsule` button, `OwnerCopy.notNow`, which sets done.

    It logs `invitation` as `accepted` or `dismissed`.
  - `OwnerCopy`:
    - `morningInvitation = "[owner copy: invitation to the morning poem]"`
    - `turnOn = "[owner copy: turn on]"`
    - `notNow = "[owner copy: not now]"`
  - The poem-link handler in `RootView`, for both URLs and notification taps:
    1. `await library.fetchPoem(id)`.
    2. On success: switch to the first tab, `paths.navigate(.reader(ReaderContext(single: PoemSummary(poem))), in: .new, split:)`, and log `daily_open` with the link's `source`.
    3. On failure: do nothing.

    The handler lives in `wuserade/Shell/PoemLinkOpener.swift` as `enum PoemLinkOpener { static func open(id: Int, fetch: (Int) async throws -> Poem, navigate: (Poem) -> Void) async }`, so it can be tested without views.
  - The notification tap builds `DeepLink.poemURL(id, source: "notification")` from `userInfo["poemId"]` and hands it to the same handler.
- The app records a visit day each time the scene becomes active.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func `Round-trips a poem link`()       // poem(from: poemURL(4130, source: "widget")) == (4130, "widget")
@Test func `Rejects other links`()           // the Google callback URL, wuserade://poem/abc
@Test func `linkToMissingPoemOpensNothing`() async   // fetch throws -> navigate never called
@Test func `Invitation shows on the third day only until answered`()
@Test func `Same day twice is one visit`()
```

- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run every Swift test, then on the simulator** open `xcrun simctl openurl booted "wuserade://poem/<a real id>?source=widget"` and check the reader opens.

### Task 13: The widget extension

**Files:**
- Create a new target `WuseradeWidgets`: a widget extension, bundle `com.nart.wuserade.widgets`, iOS 17.0, App Group `group.com.nart.wuserade`, embedded in the app. Its synced folder `WuseradeWidgets/` holds:
  - `WuseradeWidgets.swift` (the `@main WidgetBundle`)
  - `DailyProvider.swift`
  - `DaysPoemWidget.swift` (`systemMedium`)
  - `SmallPoemWidget.swift` (`systemSmall`, with an `AppIntent` configuration)
  - `LockPoemWidget.swift` (`accessoryRectangular`)
  - `WidgetCopy.swift`
  - `WidgetPalette.swift`
  - `Info.plist`, which lists the Alegreya files in `UIAppFonts`
  - `WuseradeWidgets.entitlements`
- Modify:
  - `project.pbxproj`: add the target; add `wuserade/Shared` to it; add the Alegreya font files to its resources
  - `wuserade/Shared/DailyCache.swift`, if the widget needs a read-only path
- Test: `wuseradeTests/DailyProviderTests.swift`. Put `DailyProvider`'s pure parts, `entries(for:cached:now:)` and `restURL(date:)`, in `wuserade/Shared/DailyTimeline.swift`, so the app's test target covers them.

**Interfaces:**
- Consumes: `DailyPicks`, `DailyDate`, `DailyCache.shared`, `FirestoreREST` and `DeepLink` (Tasks 7 and 12).
- Produces:
  - `enum DailyTimeline`:
    - `static func restURL(date: String) -> URL` returns `https://firestore.googleapis.com/v1/projects/wuserade/databases/(default)/documents/daily/{date}`.
    - `static func entries(for picks: DailyPicks?, now: Date, timeZone: TimeZone) -> [DailyEntry]` returns one entry at `now` and one at the next local midnight, which carries no picks so the widget refetches.
  - `struct DailyEntry: TimelineEntry { date: Date; picks: DailyPicks? }`
  - `DailyProvider: AppIntentTimelineProvider` works like this:
    1. Fetch `restURL(DailyDate.string(for: now))` with `URLSession`.
    2. On success, save it to `DailyCache.shared`.
    3. On failure, use the cache, even if it is from an earlier day. The widget's head shows the cached document's date.
    4. Use the timeline policy `.after(next local midnight)`.
  - The widgets:
    - **Medium:** a head with the lozenge, `WidgetCopy.daysPageLabel` and the `dd.MM` date, then the title in small caps, the poet, and up to 4 lines of the first stanza. The whole widget links to `DeepLink.poemURL(poem.id, source: "widget")`.
    - **Small:** the short poem (default) or the day's poem, chosen by `SmallPoemIntent.kind`: title, poet and the first 2 lines.
    - **Lock screen:** `"<title> · <poet>"`, then the first line.
  - `WidgetCopy`:
    - `daysPageLabel = "[owner copy: day’s page label]"`
    - `daysPoemName = "[owner copy: widget: day’s poem]"`
    - `daysPoemDescription = "[owner copy: widget: day’s poem, description]"`
    - `smallName = "[owner copy: widget: a short poem]"`
    - `smallDescription = "[owner copy: widget: a short poem, description]"`
    - `lockName = "[owner copy: widget: lock screen]"`
    - `lockDescription = "[owner copy: widget: lock screen, description]"`
    - `kindShort = "[owner copy: short poem]"`
    - `kindDay = "[owner copy: day’s poem]"`
- An empty state, when there is no cache and no network, shows only the lozenge and the app name. Never a placeholder poem.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func `REST URL for a date`()
@Test func `Timeline refreshes at the next local midnight`()  // now 2026-10-29T20:00Z in Europe/Moscow -> second entry at 2026-10-29T21:00Z
@Test func `Decodes a real REST response fixture`() throws    // fixture: the document Task 3 writes, as REST JSON
```

- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Add the target and implement the widgets.** Build the app scheme. Embedding the widget must not break the app's tests.
- [ ] **Step 4: Run every Swift test, then check on the simulator:**
  - add all three widgets;
  - with the Firestore emulator unavailable, they must show the cached document or the empty state;
  - check paper and night appearances against mockup screens 2 and 3;
  - tapping opens the reader through Task 12's handler.

  Save screenshots to the scratchpad.

### Task 14: Privacy, documentation and a whole-feature check

**Files:**
- Modify:
  - `firebase/hosting/privacy/index.html`
  - `wuserade/PrivacyInfo.xcprivacy`
  - `firebase/admin/README.md` (rebuild re-syncs the daily documents)
- Create: `firebase/functions/README.md`, covering setup, tests, the three functions and the owner's deploy steps

**Interfaces:**
- The privacy page gains two entries under "What we collect":
  - *Poems you have read*: the poem's ID and the time you first read it, saved under your account in Cloud Firestore (europe-west3), used only to suggest poems you haven't read, and deleted with your account.
  - *Morning poem settings*: your time zone, chosen time and push token, saved under your account to send the morning poem, and deleted when you turn it off, sign out or delete your account.

  Update "Last updated" to the release date.
- `PrivacyInfo.xcprivacy` gains the collected data type `NSPrivacyCollectedDataTypeProductInteraction`, linked to the user, not used for tracking, with purpose `NSPrivacyCollectedDataTypePurposeAppFunctionality`.
- `firebase/functions/README.md` lists the owner's deploy order, from the spec's Rollout section:
  1. Blaze, with a budget alert.
  2. `views` (or `views --json`).
  3. `firebase deploy --only firestore:rules,firestore:indexes,functions`.
  4. Run `writeDailyPicks` once from the console.
  5. `firebase deploy --only hosting` for the privacy page.
  6. Ship the app, and update the App Store privacy labels (Product Interaction, linked, app functionality).

- [ ] **Step 1: Make the privacy page and manifest changes.** Then check that `plutil -lint wuserade/PrivacyInfo.xcprivacy` prints `OK`.
- [ ] **Step 2: Write the functions README and update the admin README.**
- [ ] **Step 3: Run every suite:**
  - Swift tests;
  - admin and functions tests on the emulator;
  - rules tests.

  All must pass. Record the counts.
- [ ] **Step 3a: Estimate the cost.** Estimate daily Firestore reads at the current audience from Analytics' daily active users: Home loads, widget refreshes, `keepReading` calls (each at most 1 + 25 + 20 reads), and the push job. Report it to the owner if it comes out above the free 50,000 reads a day.
- [ ] **Step 4: Run an end-to-end check on the emulator.**
  1. Load fixture content into the Firestore emulator through the admin tool.
  2. Run `write_missing_days` and `send_due`, with a fake sender, from a short script.
  3. Point a debug build at the emulator, then check:
     - Home shows the three daily sections;
     - a poem read for 10 seconds appears in `users/{uid}/reads`;
     - keep reading hides it when calling `keep_reading` directly.
  4. Report what could not be checked without production: real FCM delivery, and the widget fetching from the live REST endpoint.
