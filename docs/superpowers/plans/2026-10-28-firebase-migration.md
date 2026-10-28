# Wuserade Firebase Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Wuserade iOS app from the Django/Render API to Firebase. It reads content from Firestore through a cached catalog, adds Apple/Google/anonymous accounts with synced likes and in-app deletion, and hosts a privacy policy.

**Architecture:** Content (poems, authors, themes) lives in Firestore and is written only by a Python admin tool. The tool also builds `catalog/*` chunks and `meta/content`. The app caches the catalog on disk and builds every list and search from it, reading one `poems/{id}` document per opened poem. Accounts use Firebase Auth (a silent anonymous account, upgraded by linking Apple or Google), and likes live in `users/{uid}/likes`.

**Tech Stack:** Swift 5 / SwiftUI / Observation (iOS 17), Firebase iOS SDK (Auth, Firestore, Analytics, Messaging), GoogleSignIn-iOS, AuthenticationServices, SwiftData (legacy likes only), XCTest. Python 3.11 + `firebase-admin` + `psycopg[binary]` + pytest. Node + `@firebase/rules-unit-testing` for rules tests. Firebase CLI via `npx -y firebase-tools@latest`.

**Spec:** `docs/superpowers/specs/2026-10-28-firebase-migration-design.md`. Read it before starting any task.

## Global Constraints

- App deployment target stays **iOS 17.0**; Swift language mode stays **5**.
- Firebase project **`wuserade`**; Firestore `(default)` database, **Standard** edition, location **`europe-west3`**.
- All emulator tests use project ID **`demo-wuserade`** so they can never touch production.
- Document IDs are `String(id)` of the existing Django Int IDs, and every content document also stores `id: Int`.
- Collection and field names are exactly as in the spec's Data model section (`poems`, `authors`, `themes`, `catalog`, `meta/content`, `users/{uid}`, `users/{uid}/likes/{poemId}`).
- Catalog chunk size: **2000** entries.
- Search normalization: lowercase, then map each of `Ӏ ӏ I i l 1` to **`ӏ`** (U+04CF), then trim whitespace.
- Never `import FirebaseFirestoreSwift`; Codable support is in `FirebaseFirestore` (SDK 11+).
- No secrets in the repo: `DATABASE_URL`, service-account keys and `.env` files stay out of git (add `firebase/admin/.env` and `*.json` keys to `.gitignore`).
- New user-facing strings are Kabardian placeholders marked `// TODO(owner): copy`.
- Privacy policy URL: `https://wuserade.com/privacy` (wuserade.com and www move to Firebase Hosting in Task 5). App Store link for update prompts: `https://apple.co/3OWuu5b`.
- Any command that touches production (database creation, `firebase deploy`, `migrate`/`rebuild` without the emulator) needs the owner's explicit go-ahead in chat at the time it runs.
- iOS test command: `xcodebuild test -project Wuserade.xcodeproj -scheme Wuserade -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:WuseradeTests/<TestClass>`.
- Emulator command prefix (run from `firebase/`): `npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore "<cmd>"`.

## Review Focus

1. **First launch with no network and no cache:** lists show an empty state with a retry (not an endless spinner), and the catalog loads when the app comes back to the foreground online. Tests in Task 8.
2. **Tapping like before an account exists** (anonymous sign-in still pending or failed offline): nothing is written, nothing crashes, and the button shows as not liked. Tests in Task 12.
3. **Cancelling the Apple or Google sheet:** no error alert, and the account state is unchanged. Tests in Task 11.
4. **Opening a liked poem offline:** `PoemView` shows the like's stored snapshot instead of failing. Tests in Task 10.
5. **Switching accounts** (sign out, sign in to another account, delete): the likes listener for the old uid stops, and the Liked tab never shows the previous account's likes. Tests in Task 12.

---

## Prerequisites (owner)

- [ ] Commit the current uncommitted Xcode project upgrade on `navigation` (`project.pbxproj` synchronized folders, schemes, `Package.resolved`, `PersistedPoem`/`PersistedAuthor` `let`→`var`, `HTTPClient` status check). These are the owner's changes. Then create branch `firebase-migration` from it.
- [ ] Have ready: Google Cloud CLI logged in (`gcloud auth application-default login`), Node 20+, Python 3.11+, and the Render `DATABASE_URL` (kept in `firebase/admin/.env`, not committed).

---

## Phase A: Firebase backend (repo `firebase/`)

### Task 1: Firebase config, security rules, rules tests

**Files:**
- Create: `firebase/firebase.json`, `firebase/.firebaserc`, `firebase/firestore.rules`, `firebase/firestore.indexes.json`
- Create: `firebase/rules-tests/package.json`, `firebase/rules-tests/rules.test.mjs`
- Modify: `.gitignore` (add `firebase/**/node_modules`, `firebase/admin/.env`, `firebase/**/*-key.json`, `firebase/**/.venv`, `firebase/*.log`)

**Interfaces:**
- Produces: the rules contract later tasks write against. A like doc has exactly `poemId:int, likedAt:timestamp, title:string, authorId:int, authorName:string, text:string`, with `poemId == int(docId)`. A user doc has `createdAt:timestamp` and optional `displayName:string`.

- [ ] **Step 1: Scaffold config**

`.firebaserc` default project `wuserade`. `firebase.json` contains `firestore.rules`, `firestore.indexes.json`, emulator ports (firestore 8080, hosting 5050, ui disabled), and a `hosting` block with `public: "hosting"` and `cleanUrls: true`. `firestore.indexes.json`: `indexes: []` and `fieldOverrides` that disable indexing (`indexes: []`) for `poems.text` and `catalog.entries`.

- [ ] **Step 2: Write the failing rules tests** in `rules.test.mjs` (node:test + `@firebase/rules-unit-testing`, projectId `demo-wuserade`):

```js
test('anyone can read content', ...)          // unauth get of poems/1, authors/1, themes/1, catalog/0, meta/content → assertSucceeds
test('nobody can write content', ...)         // auth 'alice' set poems/1, catalog/0, meta/content → assertFails
test('owner can write a valid like', ...)     // alice set users/alice/likes/5 {poemId:5, likedAt: Timestamp.now(), title:'т', authorId:1, authorName:'а', text:'x'} → succeeds
test('like poemId must match doc id', ...)    // users/alice/likes/5 with poemId:6 → fails
test('like must have exact fields', ...)      // missing text → fails; extra field 'foo' → fails; authorId:'1' (string) → fails
test('cannot touch another user', ...)        // alice get/set users/bob/likes/5 and users/bob → fails
test('owner can create, read, delete own user doc and likes', ...)
test('unknown collections are denied', ...)   // alice get/set other/1 → fails
```

`package.json`: `"type":"module"`, script `"test": "node --test"`, devDependencies `@firebase/rules-unit-testing`, `firebase`.

- [ ] **Step 3: Run tests and confirm they fail**

Run (in `firebase/`): `npm --prefix rules-tests install && npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore "npm --prefix rules-tests test"`
Expected: FAIL (the default rules deny everything, so the read and owner tests fail).

- [ ] **Step 4: Write `firestore.rules`** that implement the spec's Security rules section and the contract above (use `request.resource.data.keys().hasOnly([...])` + `hasAll([...])` + type checks; `poemId == int(likeId)`).

- [ ] **Step 5: Run tests and confirm they pass.** Same command. Expected: all 8 pass.

- [ ] **Step 6: Commit** `feat(firebase): add Firestore rules, indexes and rules tests`

---

### Task 2: Admin tool, catalog builder (pure functions)

**Files:**
- Create: `firebase/admin/pyproject.toml` (deps `firebase-admin`, `psycopg[binary]`, `python-dotenv`; dev `pytest`)
- Create: `firebase/admin/wuserade_admin/__init__.py`, `firebase/admin/wuserade_admin/models.py`, `firebase/admin/wuserade_admin/catalog.py`
- Test: `firebase/admin/tests/test_catalog.py`

**Interfaces:**
- Produces (`models.py`): frozen dataclasses `ThemeRow(id:int, title:str)`, `AuthorRow(id:int, name:str, bio:str, photo:str|None)`, `PoemRow(id:int, title:str, text:str, author_id:int, theme_id:int|None, created_at:datetime, updated_at:datetime)`.
- Produces (`catalog.py`):
  - `CHUNK_SIZE = 2000`
  - `catalog_entries(poems: list[PoemRow], authors: dict[int, AuthorRow]) -> list[dict]`. Each entry is `{"id","title","authorId","authorName","themeId","createdAt"}`, sorted by `id` ascending.
  - `chunk(entries: list[dict], size: int = CHUNK_SIZE) -> list[list[dict]]`
  - `poem_document(p: PoemRow, author_name: str) -> dict`: the spec's `poems/{id}` fields with `submittedBy: None`.
  - `author_document(a: AuthorRow, poems_count: int) -> dict`, `theme_document(t: ThemeRow, poems_count: int) -> dict`
  - `meta_document(themes, authors, poems, catalog_version: int, chunk_count: int, minimum_app_version: str | None) -> dict`. `authors` here includes only authors with ≥1 poem, as `{id,name,poemsCount}`, sorted by id. `themes` includes all themes as `{id,title,poemsCount}`. Also `nextPoemId = max(poem ids) + 1`.

- [ ] **Step 1: Write failing tests** in `test_catalog.py`:
  - `test_chunk_splits_4500_into_2000_2000_500`
  - `test_entry_has_exact_keys_and_author_name`: keys == `{"id","title","authorId","authorName","themeId","createdAt"}`
  - `test_theme_id_none_is_preserved`
  - `test_meta_excludes_authors_without_poems_and_counts_correctly`
  - `test_meta_next_poem_id_is_max_plus_one`: ids [5, 4130, 12] → 4131
  - `test_realistic_chunk_fits_firestore_limit`: 2000 entries with 60-char Cyrillic titles and 30-char names → `len(json.dumps(chunk, ensure_ascii=False, default=str).encode()) < 900_000`
  - `test_poem_document_fields`: equals the spec's field set, with `submittedBy` None
- [ ] **Step 2: Run** `cd firebase/admin && python -m pytest -q tests/test_catalog.py`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `models.py` and `catalog.py` per the interfaces.
- [ ] **Step 4: Run** the same command. Expected: 7 passed.
- [ ] **Step 5: Commit** `feat(admin): catalog and document builders`

---

### Task 3: Admin tool, Firestore store, Postgres source, CLI

**Files:**
- Create: `firebase/admin/wuserade_admin/source.py`, `firebase/admin/wuserade_admin/store.py`, `firebase/admin/wuserade_admin/__main__.py`
- Create: `firebase/admin/README.md` (how to run each command, credentials via ADC, `.env` for `DATABASE_URL`)
- Test: `firebase/admin/tests/test_store_emulator.py`

**Interfaces:**
- Consumes: Task 2's models and builders.
- Produces:
  - `source.read_postgres(dsn: str) -> tuple[list[ThemeRow], list[AuthorRow], list[PoemRow]]` (tables `poems_theme`, `poems_author`, `poems_poem`; `category_id` → `theme_id`; ignore the old `theme` CharField).
  - `store.upsert_content(db, themes, authors, poems) -> None`: batched writes of at most 500 per batch. Author names are denormalized onto poems.
  - `store.load_content(db) -> tuple[list[ThemeRow], list[AuthorRow], list[PoemRow]]`
  - `store.rebuild(db, minimum_app_version: str | None = None) -> RebuildResult`: recomputes `poemsCount` on authors and themes, writes `catalog/0..n-1` with `version = previous catalogVersion + 1` (1 if none), deletes stale `catalog/{k}` for k ≥ n, then writes `meta/content` last. `RebuildResult(catalog_version:int, chunks:int, poems:int, authors_with_poems:int, themes:int)`.
  - `store.add_poem(db, title: str, text: str, author_id: int, theme_id: int | None) -> int`: reads `meta/content.nextPoemId` in a transaction, writes `poems/{id}`, returns the id. The caller then runs `rebuild`.
  - CLI: `python -m wuserade_admin migrate [--dsn URL]` (default `DATABASE_URL` from env/.env) prints Postgres vs Firestore counts and exits non-zero if they differ. `python -m wuserade_admin rebuild [--min-version X]`. `python -m wuserade_admin add-poem --title T --text-file F --author-id N [--theme-id N]`. Credentials come from ADC. Project `wuserade` unless `FIRESTORE_EMULATOR_HOST` is set, in which case `demo-wuserade`.

- [ ] **Step 1: Write failing emulator tests** in `test_store_emulator.py`. Skip unless `FIRESTORE_EMULATOR_HOST` is set, and use a fixture that deletes all docs before each test.
  - `test_upsert_then_rebuild_writes_catalog_meta_and_counts`: 3 themes, 4 authors (one without poems), 2,500 poems → `RebuildResult(catalog_version=1, chunks=2, poems=2500, authors_with_poems=3, themes=3)`; `meta/content.catalogChunks == 2`; `authors/{id}.poemsCount` correct
  - `test_rebuild_bumps_version`: two rebuilds → `catalogVersion == 2`, and every chunk doc has `version == 2`
  - `test_rebuild_removes_stale_chunks`: 2,500 poems → rebuild; delete 1,000 poems → rebuild → `catalog/1` exists only if needed, and `catalog/2` does not exist
  - `test_upsert_is_idempotent`: upsert the same rows twice → document counts unchanged
  - `test_add_poem_uses_next_id_and_appears_after_rebuild`: returns `nextPoemId`; after rebuild, the entry is present and `nextPoemId` incremented
- [ ] **Step 2: Run** (in `firebase/`): `npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore "cd admin && python -m pytest -q"`. Expected: FAIL (functions missing).
- [ ] **Step 3: Implement** `source.py`, `store.py`, `__main__.py`.
- [ ] **Step 4: Run** the same command. Expected: Task 2 and Task 3 tests all pass.
- [ ] **Step 5: Commit** `feat(admin): Firestore store, Postgres source and CLI`

---

### Task 4: Privacy policy page

**Files:**
- Create: `firebase/hosting/privacy/index.html` (self-contained HTML, inline CSS, readable on a phone, dark-mode aware)

- [ ] **Step 1: Draft the policy in English.** Cover exactly what the spec's Privacy policy section lists: sign-in data (uid, plus the email and name that Apple/Google share, including Apple private relay), likes, Firebase Analytics usage data tied to the uid, the FCM token, in-app account deletion and what it removes, data processors (Google Firebase), and contact `astemirboziy@gmail.com`. Add a "Last updated" date and a placeholder for an optional Kabardian/Russian version.
- [ ] **Step 2: Verify it serves.** Run (in `firebase/`): `npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only hosting "curl -sfL http://127.0.0.1:5050/privacy | grep -q 'Wuserade'"`. Expected: exit 0.
- [ ] **Step 3: Commit** `feat(hosting): privacy policy page`. The owner reviews the wording before it is deployed in Task 5.

---

### Task 5: Provision production and migrate data (owner + agent)

Every agent step here touches production and runs only after the owner says go in chat.

- [ ] **Step 1 (owner):** Upgrade project `wuserade` to Blaze, and set a budget alert in Google Cloud Billing (owner picks the amount).
- [ ] **Step 2 (owner):** In Firebase console → Authentication, enable **Anonymous**, **Google** and **Apple**. For Apple, enter the Services ID, Apple Team ID, Key ID and private key of a Sign in with Apple key (this is required for `revokeToken`). Then download the new `GoogleService-Info.plist` (it now contains `CLIENT_ID`/`REVERSED_CLIENT_ID`) and replace `wuserade/GoogleService-Info.plist`.
- [ ] **Step 3 (agent):** Create the database: `npx -y firebase-tools@latest firestore:databases:create "(default)" --location europe-west3 --edition standard --project wuserade`. Verify with `firestore:databases:get "(default)"`: edition STANDARD, location europe-west3.
- [ ] **Step 4 (agent):** Deploy: `npx -y firebase-tools@latest deploy --only firestore:rules,firestore:indexes,hosting --project wuserade`. Verify that `https://wuserade.web.app/privacy` loads.
- [ ] **Step 5 (agent):** `cd firebase/admin && python -m wuserade_admin migrate && python -m wuserade_admin rebuild`. Expected: counts match Postgres (4,091+ poems, 14 themes, at time of writing). Spot-check `poems/4130` in the console against `https://wuserade.onrender.com/api/v1/poems/4130/`.
- [ ] **Step 6 (owner, after Step 4):** Move the domain to Firebase Hosting.
  - In Firebase console → Hosting → Add custom domain, add `wuserade.com`, then add `www.wuserade.com` with "Redirect to wuserade.com".
  - At GoDaddy (DNS for wuserade.com), replace the current records that point at Render (the apex `A` record `216.24.57.1` and the `www` `CNAME` to `wuserade-front.onrender.com`) with exactly the records the Firebase console shows, including its `TXT` verification record.
  - Remove the custom domains from the `wuserade-front` service in Render.
  - Wait until the console shows the domain as Connected (the certificate can take up to 24 hours).
- [ ] **Step 7 (agent):** Verify, following redirects, that `https://wuserade.com/` shows the home page, and that `https://wuserade.com/privacy` and `https://www.wuserade.com/privacy` both end at the policy with a 200 (Hosting may redirect `/privacy` to `/privacy/`).
- [x] **Step 8:** The new `GoogleService-Info.plist` and the `REVERSED_CLIENT_ID` URL scheme landed as their own commit (bd44d0d), since Task 6 had already shipped.

---

## Phase B: iOS content from Firestore

### Task 6: Dependencies, capabilities, test folder

**Files:**
- Modify: `Wuserade.xcodeproj/project.pbxproj`, `Package.resolved`, `wuserade/Wuserade.entitlements`, `wuserade/Info.plist`, `wuserade/GoogleService-Info.plist`

- [ ] **Step 1:** Bump `firebase-ios-sdk` to the current major release ("Up to Next Major"). Add the products `FirebaseAuth` and `FirebaseFirestore` to the `Wuserade` target. Add package `https://github.com/google/GoogleSignIn-iOS` (current major) with product `GoogleSignIn`. Add `FirebaseFirestore` to `WuseradeTests` too (the tests use `Firestore.Encoder/Decoder`).
- [ ] **Step 2:** Add `com.apple.developer.applesignin = ["Default"]` to `Wuserade.entitlements`. Add a `CFBundleURLTypes` entry to `Info.plist` with the `REVERSED_CLIENT_ID` value from the new `GoogleService-Info.plist`.
- [ ] **Step 3:** Convert the `wuseradeTests` group into a synchronized folder (Xcode: right-click → Convert to Folder), so new test files are compiled without project edits. Delete the template `wuseradeTests.swift` contents (keep the file compiling, or remove it).
- [ ] **Step 4: Verify.** Run `xcodebuild build -project Wuserade.xcodeproj -scheme Wuserade -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`. Expected: BUILD SUCCEEDED, with existing Analytics/Messaging code compiling against the new SDK (fix any renamed APIs).
- [ ] **Step 5: Commit** `chore(ios): add FirebaseAuth, Firestore, GoogleSignIn; Apple sign-in capability`

---

### Task 7: Content models, catalog and search (pure Swift)

**Files:**
- Create: `wuserade/Models/PoemSummary.swift`, `wuserade/Models/Catalog.swift`, `wuserade/Models/ContentMeta.swift`, `wuserade/Services/Search/CatalogSearch.swift`
- Test: `wuseradeTests/CatalogTests.swift`, `wuseradeTests/CatalogSearchTests.swift`

**Interfaces:**
- Produces:
  - `struct PoemSummary: Codable, Identifiable, Hashable { let id: Int; let title: String; let authorId: Int; let authorName: String; let themeId: Int?; let createdAt: Date; var author: Author }`
  - `struct CatalogChunk: Codable { let version: Int; let entries: [PoemSummary] }`
  - `struct Catalog: Codable, Equatable { let version: Int; let entries: [PoemSummary]; func newestFirst() -> [PoemSummary]; func poems(byAuthor id: Int) -> [PoemSummary]; func poems(inTheme id: Int) -> [PoemSummary] }`. All three return newest first.
  - `struct AuthorEntry: Codable, Hashable { let id: Int; let name: String; let poemsCount: Int; var author: Author }`
  - `struct ContentMeta: Codable, Equatable { let catalogVersion: Int; let catalogChunks: Int; let authors: [AuthorEntry]; let themes: [Category]; let nextPoemId: Int; let minimumAppVersion: String? }` (make `Category` `Hashable`/`Equatable`)
  - `enum CatalogSearch { static func normalize(_ text: String) -> String; static func search(_ query: String, in entries: [PoemSummary]) -> [PoemSummary] }`. Ranking: title-prefix matches, then other title matches, then author-only matches. Within each group, order by title.

- [ ] **Step 1: Write failing tests.**
  - `CatalogSearchTests`:
    - `testNormalizeMapsPalochkaVariants`: `normalize("КӀуэ")`, `normalize("Кlуэ")`, `normalize("К1уэ")`, `normalize("КIуэ")`, `normalize("кӏуэ")` all `== "кӏуэ"`
    - `testNormalizeTrims`: `normalize("  Псы ") == "псы"`
    - `testWhitespaceQueryReturnsNothing`
    - `testMatchesTitleSubstringAcrossPalochkaVariants`: `search("цlык", in: [summary(title: "ПСЫ ЦӀЫКӀУ")])` returns it
    - `testMatchesAuthorName`: `search("лашэ", ...)` finds a poem by "Агънокъуэ Лашэ"
    - `testTitlePrefixRanksFirst`: query "псы" orders "Псы цӀыкӀу" before "Си псы"
  - `CatalogTests`:
    - `testNewestFirst`
    - `testPoemsByAuthorFilters`
    - `testPoemsInThemeExcludesNil`
    - `testChunkDecodesFromFirestoreData`: `Firestore.Decoder().decode(CatalogChunk.self, from: ["version": 3, "entries": [["id": 1, "title": "t", "authorId": 2, "authorName": "a", "themeId": NSNull(), "createdAt": Timestamp(date: date)]]])` produces `themeId == nil` and the right `createdAt`
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/CatalogSearchTests -only-testing:WuseradeTests/CatalogTests`. Expected: FAIL (types missing).
- [ ] **Step 3: Implement** the types above.
- [ ] **Step 4: Run** the same command. Expected: all pass.
- [ ] **Step 5: Commit** `feat(ios): catalog models and on-device search`

---

### Task 8: Content repository and catalog store with disk cache

**Files:**
- Create: `wuserade/Services/Content/ContentRepository.swift`, `wuserade/Services/Content/FirestoreContentRepository.swift`, `wuserade/Services/Content/CatalogCache.swift`, `wuserade/Services/Content/CatalogStore.swift`
- Test: `wuseradeTests/CatalogStoreTests.swift` (includes `FakeContentRepository`)

**Interfaces:**
- Consumes: Task 7 types.
- Produces:
  - `protocol ContentRepository: Sendable { func fetchMeta() async throws -> ContentMeta; func fetchCatalogChunk(index: Int) async throws -> CatalogChunk; func fetchPoem(id: Int) async throws -> Poem }`
  - `struct FirestoreContentRepository: ContentRepository`: reads `meta/content`, `catalog/{index}`, and `poems/{id}`. The last one decodes a private `PoemRecord { id, title, text, authorId, authorName }` into `Poem(id:title:author:content:)`.
  - `struct CachedContent: Codable { let meta: ContentMeta; let catalog: Catalog }`
  - `struct CatalogCache { init(directory: URL); func load() -> CachedContent?; func save(_ content: CachedContent) throws }`. The file is `catalog-cache.json`. `CatalogCache.default` uses Application Support.
  - `@MainActor @Observable final class CatalogStore { init(repository: ContentRepository, cache: CatalogCache); let repository: ContentRepository; private(set) var catalog: Catalog?; private(set) var meta: ContentMeta?; private(set) var isLoading: Bool; private(set) var lastError: Error?; var authors: [Author]; var themes: [Category]; func refresh() async }`
    - `init` loads the cache synchronously.
    - `refresh()` always fetches meta. It fetches all chunks concurrently only when `meta.catalogVersion != catalog?.version`. It accepts the new catalog only if every chunk's `version == meta.catalogVersion`. Otherwise it keeps the old catalog and sets `lastError`. Accepted content is saved to the cache. Errors never clear existing data.

- [ ] **Step 1: Write failing tests** (temp directory per test):
  - `testFreshStoreLoadsAndCachesCatalog`: fake meta v3 with 2 chunks (3 + 2 entries) → `catalog.version == 3`, `entries.count == 5`, cache file exists
  - `testSecondStoreReadsCacheWithoutNetwork`: new store, same dir, fake throws → `catalog.version == 3` before and after `refresh()`
  - `testSameVersionDoesNotRefetchChunks`: `fake.chunkCalls == 0` on the second refresh
  - `testNewVersionRefetches`
  - `testChunkVersionMismatchKeepsOldCatalog`: meta v4, chunk 1 still v3 → catalog stays v3, `lastError != nil`
  - `testOfflineFirstLaunchEndsLoadingWithError` (Review Focus 1): empty cache, fake throws → `isLoading == false`, `catalog == nil`, `lastError != nil`
  - `testAuthorsAndThemesComeFromMeta`
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/CatalogStoreTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the four files.
- [ ] **Step 4: Run** the same command. Expected: all pass.
- [ ] **Step 5: Commit** `feat(ios): Firestore content repository and cached catalog store`

---

### Task 9: Lists and search read from the catalog

**Files:**
- Modify: `wuserade/wuseradeApp.swift`: create one `CatalogStore(repository: FirestoreContentRepository(), cache: .default)` and inject it with `.environment(_:)`. Call `refresh()` on launch and whenever `scenePhase` becomes `.active`.
- Modify: `wuserade/ViewModels/PoemsViewModel.swift`: becomes a non-generic paging helper.
- Modify: `wuserade/ViewModels/AuthorsViewModel.swift`: non-generic. Keeps `groupedAndSortedAuthors` and the Kabardian alphabet sort, and takes `authors: [Author]` as input.
- Modify: `wuserade/ViewModels/SearchViewModel.swift`: uses `CatalogSearch` and searches as you type.
- Delete: `wuserade/ViewModels/CategoriesViewModel.swift`
- Modify views: `Views/Poems/PoemsListView.swift`, `Views/Poems/MainView.swift`, `Views/Poems/CategoriesView.swift`, `Views/Poems/PoemCategoryView.swift`, `Views/AuthorsListView.swift`, `Views/AuthorView.swift`, `Views/SearchView.swift`, `Views/Poems/PoemRow.swift`, `Views/Poems/PoemLabel.swift`
- Test: `wuseradeTests/PoemsViewModelTests.swift`, `wuseradeTests/AuthorsViewModelTests.swift`

**Interfaces:**
- Consumes: `CatalogStore`, `Catalog`, `CatalogSearch` (Tasks 7–8).
- Produces:
  - `PoemRow(poemID: Int, title: String, authorName: String)` and `PoemLabel(title:authorName:)`. Every list uses these. Task 10 adds `preloaded:`.
  - `@Observable final class PoemsViewModel { static let pageSize = 20; private(set) var visibleCount: Int; func visible(_ all: [PoemSummary]) -> ArraySlice<PoemSummary>; func loadMoreIfNeeded(current: PoemSummary, in all: [PoemSummary]) }`. It loads more when `current` is 10 or fewer from the end of the visible slice.
  - `@Observable final class AuthorsViewModel { func grouped(_ authors: [Author]) -> [(key: String, value: [Author])] }`

- [ ] **Step 1: Write failing tests.**
  - `PoemsViewModelTests.testStartsWithTwenty`: 45 entries → 20 visible
  - `PoemsViewModelTests.testLoadsNextPageNearEnd`: `loadMoreIfNeeded` at index 10 → 40; again near the end → 45 (capped)
  - `AuthorsViewModelTests.testGroupsByKabardianAlphabet`: names `["Хьэбэч", "Агънокъуэ Лашэ", "Бэчыжь", "Апажэ"]` produce group keys in order `["а", "б", "хь"]`, with "Агънокъуэ…" before "Апажэ"
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/PoemsViewModelTests -only-testing:WuseradeTests/AuthorsViewModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the view-model changes, then switch each view to `@Environment(CatalogStore.self)`:
  - Home tab ("Усэщlэхэр"): `catalog.newestFirst()` paged by `PoemsViewModel`.
  - Themes: `store.themes`.
  - `PoemCategoryView`: `catalog.poems(inTheme:)`.
  - Authors: `store.authors` grouped.
  - `AuthorView`: `catalog.poems(byAuthor:)`.
  - Search: `CatalogSearch.search(query, in: catalog.entries)` on every query change.

  Each list shows `ContentUnavailableView` with a retry button calling `store.refresh()` when `catalog == nil && !isLoading` (Review Focus 1). Pull-to-refresh calls `store.refresh()`.
- [ ] **Step 4: Run** the same tests (expect pass), then the build command.
- [ ] **Step 5: Manual check in the simulator.** Check that the home list shows the newest poems and pages on scroll, themes and authors list correctly, an author's and a theme's poems show, and search finds "цlыкl" variants. Then quit, enable airplane mode, and relaunch: lists and search still work from cache.
- [ ] **Step 6: Commit** `feat(ios): build lists and search from the cached catalog`

---

### Task 10: Poem screen from Firestore; remove the old networking

**Files:**
- Modify: `wuserade/ViewModels/PoemViewModel.swift`, `wuserade/Views/Poems/PoemView.swift`, `wuserade/Views/Poems/PoemRow.swift`
- Delete: `wuserade/Services/Base/` (all), `wuserade/Services/Endpoints/` (all), `wuserade/Services/PoemsService.swift`, `AuthorsService.swift`, `CategoriesService.swift`, `wuserade/Models/PoemsResponse.swift`, and the now-unused `Constants.ErrorMessages` entries
- Test: `wuseradeTests/PoemViewModelTests.swift`

**Interfaces:**
- Consumes: `ContentRepository` (Task 8).
- Produces:
  - `@MainActor @Observable final class PoemViewModel { init(repository: ContentRepository, preloaded: Poem? = nil); private(set) var poem: Poem?; private(set) var loadFailed: Bool; func load(id: Int) async }`. If `preloaded` is non-nil, it is shown at once and `load` doesn't call the repository.
  - `PoemView(poemID: Int, preloaded: Poem? = nil)` builds its view model from `@Environment(CatalogStore.self).repository` and shows a retry state when `loadFailed`.
  - `PoemRow(poemID:title:authorName:preloaded: Poem? = nil)` passes `preloaded` through to `PoemView`.

- [ ] **Step 1: Write failing tests:** `testLoadsPoemFromRepository`, `testFailureSetsLoadFailed`, `testPreloadedPoemSkipsRepository` (Review Focus 4: the fake records zero calls).
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/PoemViewModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement**, then delete the old networking files and fix references until the build succeeds.
- [ ] **Step 4: Run** all `WuseradeTests` and the build. Expected: pass and BUILD SUCCEEDED. `grep -rn "onrender" wuserade` returns nothing.
- [ ] **Step 5: Commit** `feat(ios): load poems from Firestore; remove Render networking`

---

## Phase C: Accounts and likes

### Task 11: Like model, likes store, account manager

**Files:**
- Create: `wuserade/Models/Like.swift`, `wuserade/Services/Likes/LikesStore.swift` (protocol + `FirestoreLikesStore`), `wuserade/Services/Likes/LikesMerge.swift`, `wuserade/Services/Likes/PendingLikesStore.swift`
- Create: `wuserade/Services/Account/AuthBackend.swift` (protocol + `FirebaseAuthBackend`), `wuserade/Services/Account/AccountManager.swift`, `wuserade/Services/Account/AppleSignInCoordinator.swift`, `wuserade/Services/Account/GoogleSignInCoordinator.swift`, `wuserade/Services/Account/SignInError.swift`
- Test: `wuseradeTests/LikeTests.swift`, `wuseradeTests/AccountManagerTests.swift` (with `FakeAuthBackend`, `FakeLikesStore` in `wuseradeTests/Fakes.swift`)

**Interfaces:**
- Produces:
  - `struct Like: Codable, Identifiable, Hashable { let poemId: Int; let likedAt: Date; let title: String; let authorId: Int; let authorName: String; let text: String; var id: Int; init(poem: Poem, likedAt: Date = .now); var poem: Poem }`
  - `enum LikesMerge { static func merge(existing: [Like], incoming: [Like]) -> [Like] }`: union by `poemId`, keeping the earliest `likedAt`, sorted by `likedAt` descending.
  - `protocol LikesStore: Sendable { func fetchLikes(uid: String) async throws -> [Like]; func observeLikes(uid: String) -> AsyncThrowingStream<[Like], Error>; func setLike(_ like: Like, uid: String) async throws; func setLikes(_ likes: [Like], uid: String) async throws; func removeLike(poemId: Int, uid: String) async throws; func ensureUserDocument(uid: String) async throws; func deleteAllData(uid: String) async throws }`. `deleteAllData` is idempotent.
  - `struct PendingLikesStore { init(defaults: UserDefaults = .standard); func save(_ likes: [Like]); func load() -> [Like]; func clear() }` (key `pendingLikesMerge`)
  - `enum SignInProvider: String, Codable { case apple = "apple.com", google = "google.com" }`
  - `struct ProviderCredential { let provider: SignInProvider; let credential: AuthCredential; let appleAuthorizationCode: String? }`
  - `struct AuthUserInfo: Equatable { let uid: String; let isAnonymous: Bool; let provider: SignInProvider?; let email: String? }`
  - `enum AuthBackendError: Error { case credentialAlreadyInUse(ProviderCredential) }`
  - `protocol AuthBackend { var currentUser: AuthUserInfo? { get }; func signInAnonymously() async throws -> AuthUserInfo; func link(_ c: ProviderCredential) async throws -> AuthUserInfo; func signIn(with c: ProviderCredential) async throws -> AuthUserInfo; func reauthenticate(with c: ProviderCredential) async throws; func revokeAppleToken(authorizationCode: String) async throws; func deleteCurrentUser() async throws; func signOut() throws }`
  - `enum AccountState: Equatable { case signedOut; case anonymous(uid: String); case signedIn(uid: String, provider: SignInProvider, email: String?); var uid: String? }`
  - `@MainActor @Observable final class AccountManager { init(auth: AuthBackend, likes: LikesStore, pending: PendingLikesStore, setAnalyticsUserID: @escaping (String) -> Void = { Analytics.setUserID($0) }); private(set) var state: AccountState; func start() async; func signIn(with c: ProviderCredential) async throws; func signOut() async throws; func deleteAccount(reauthWith c: ProviderCredential) async throws }`
  - `@MainActor final class AppleSignInCoordinator { func signIn() async throws -> ProviderCredential }` (nonce + SHA-256 via CryptoKit) and `@MainActor final class GoogleSignInCoordinator { func signIn() async throws -> ProviderCredential }` (client ID from `FirebaseApp.app()?.options.clientID`). Both throw `SignInError.cancelled` when the user cancels.
  - `enum SignInError: Error, Equatable { case cancelled; case missingToken; static func map(_ error: Error) -> Error }`. This maps `ASAuthorizationError.canceled` and `GIDSignInError.canceled` to `.cancelled`.
- `AccountManager` behaviour (from the spec's Accounts section):
  - `start()`: signs in anonymously if there's no user, then calls `ensureUserDocument`. If `pending.load()` is not empty, it merges the pending likes into the current uid (`setLikes(merge(existing, pending))`) and clears them. Finally it calls `setAnalyticsUserID(uid)`.
  - `signIn`: tries `link` first. On `.credentialAlreadyInUse(c2)`, it runs these steps in order:
    1. Fetch the anonymous likes and save them to `pending`.
    2. `deleteAllData(anonUid)` and `deleteCurrentUser()`. Ignore errors here.
    3. `signIn(with: c2)`.
    4. `ensureUserDocument`.
    5. Merge the pending likes into the existing account, then clear `pending`.

    If step 3 throws, rethrow. The pending likes stay and are merged by the next `start()`.
  - `signOut`: `auth.signOut()`, then `start()`.
  - `deleteAccount`: requires `.signedIn`. Calls `reauthenticate`, then `revokeAppleToken` for Apple (throws `SignInError.missingToken` if the code is nil), then `deleteAllData`, then `deleteCurrentUser`, then `start()`.

- [ ] **Step 1: Write failing tests.**
  - `LikeTests`:
    - `testMergeKeepsEarliestAndUnion`: existing {1@t2}, incoming {1@t1 (t1 < t2), 2@t3} → {1@t1, 2@t3}, sorted by `likedAt` desc
    - `testLikeEncodesExactlyRuleFields`: `Firestore.Encoder().encode(like).keys` == `["poemId","likedAt","title","authorId","authorName","text"]` as a set
    - `testLikeRoundTripsPoem`
  - `AccountManagerTests`:
    - `testStartSignsInAnonymouslyOnce`
    - `testStartKeepsExistingUser`
    - `testLinkSuccessKeepsUid`: state `.signedIn` with the same uid, and no likes calls
    - `testCredentialInUseMergesAnonymousLikes`: existing account {1@t2}, anonymous {1@t1, 2} → existing ends with {1@t1, 2}; the anonymous data is deleted; pending is cleared
    - `testCredentialInUseSignInFailureKeepsPendingAndNextStartMergesIt`
    - `testDeleteAppleAccountCallOrder`: `["reauthenticate","revokeAppleToken","deleteAllData","deleteCurrentUser","signInAnonymously"]`
    - `testDeleteGoogleAccountSkipsRevoke`
    - `testDeleteAccountRetryAfterFailureSucceeds`: the first `deleteCurrentUser` throws, the second call succeeds, and `deleteAllData` was called twice without error
    - `testSignOutStartsNewAnonymousAccount`
  - `SignInErrorTests.testCancellationIsMapped` (Review Focus 3): `SignInError.map(ASAuthorizationError(.canceled)) as? SignInError == .cancelled`
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/LikeTests -only-testing:WuseradeTests/AccountManagerTests -only-testing:WuseradeTests/SignInErrorTests`. Expected: FAIL.
- [ ] **Step 3: Implement** all files above. `FirestoreLikesStore` uses `users/{uid}` and `users/{uid}/likes/{poemId}`, with batched deletes in `deleteAllData`. `FirebaseAuthBackend` maps `AuthErrorCode.credentialAlreadyInUse` (using `AuthErrorUserInfoUpdatedCredentialKey`) to `AuthBackendError.credentialAlreadyInUse`.
- [ ] **Step 4: Run** the same tests. Expected: all pass. Then run the build.
- [ ] **Step 5: Commit** `feat(ios): accounts with anonymous, Apple and Google sign-in`

---

### Task 12: Likes in Firestore, Liked tab, legacy likes upload

**Files:**
- Create: `wuserade/Services/Likes/LikesController.swift`, `wuserade/Services/Likes/LegacyLikesMigrator.swift`
- Modify: `wuserade/Views/Components/LikeButton.swift`, `wuserade/Views/LikedPoemsView.swift`, `wuserade/wuseradeApp.swift`, `wuserade/Views/TabBarView.swift` (remove `Analytics.setUserID(UUID().uuidString)`)
- Test: `wuseradeTests/LikesControllerTests.swift`, `wuseradeTests/LegacyLikesMigratorTests.swift`

**Interfaces:**
- Consumes: `LikesStore`, `Like`, `AccountManager.state.uid` (Task 11).
- Produces:
  - `@MainActor @Observable final class LikesController { init(store: LikesStore); private(set) var likes: [Like]; private(set) var uid: String?; func bind(uid: String?); func isLiked(_ poemId: Int) -> Bool; func toggle(_ poem: Poem) async }`
    - `bind` cancels the previous observation and clears `likes` before observing the new uid.
    - `toggle` updates optimistically and reverts on error. With `uid == nil` it does nothing.
  - `struct LegacyLikesMigrator { init(container: ModelContainer, store: LikesStore, defaults: UserDefaults); func migrateIfNeeded(uid: String) async }` (flag key `didMigrateLocalLikes`, per device; uses `persistedDate` as `likedAt`; the flag is set only after a successful `setLikes`)
- App wiring in `wuseradeApp`:
  - Create `AccountManager`, `LikesController` and `LegacyLikesMigrator`, and inject the first two with `.environment`.
  - In a `.task`: `await account.start()`, then `likes.bind(uid:)`, then `await migrator.migrateIfNeeded(uid:)`.
  - Re-bind whenever `account.state.uid` changes (`onChange`).
- `LikeButton` reads `LikesController` and is `.disabled(likes.uid == nil)`. Fix the swapped like/unlike analytics event while rewriting it. `LikedPoemsView` lists `likes.likes` with `PoemRow(poemID:title:authorName:preloaded: like.poem)`.

- [ ] **Step 1: Write failing tests.**
  - `LikesControllerTests`:
    - `testToggleAddsThenRemoves`
    - `testToggleFailureReverts`
    - `testToggleWithoutUidDoesNothing` (Review Focus 2): the fake records zero writes, and `isLiked == false`
    - `testRebindClearsOldLikes` (Review Focus 5): bind "a" (emits {1}), then bind "b" (emits {}) → `likes` is empty and the stream for "a" is cancelled
  - `LegacyLikesMigratorTests` (in-memory `ModelContainer`, `UserDefaults(suiteName:)`):
    - `testUploadsPersistedPoemsWithPersistedDate`
    - `testSetsFlagAndDoesNotRunTwice`
    - `testFailureLeavesFlagUnset`
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/LikesControllerTests -only-testing:WuseradeTests/LegacyLikesMigratorTests`. Expected: FAIL.
- [ ] **Step 3: Implement**, then rewire `LikeButton`, `LikedPoemsView` and `wuseradeApp`.
- [ ] **Step 4: Run** all `WuseradeTests` and the build. Expected: pass.
- [ ] **Step 5: Commit** `feat(ios): sync likes through Firestore and upload on-device likes`

---

### Task 13: Account UI, privacy link, minimum-version gate

**Files:**
- Create: `wuserade/Views/Account/AccountSection.swift`, `wuserade/Views/UpdateRequiredView.swift`, `wuserade/Services/AppVersion.swift`
- Modify: `wuserade/Views/SettingsView.swift` (add the `AccountSection` at the top and a "Privacy policy" `Link` in the feedback section), `wuserade/wuseradeApp.swift` (`.onOpenURL { GIDSignIn.sharedInstance.handle($0) }`, plus an `UpdateRequiredView` full-screen cover when `!AppVersion.isSupported(current:minimum:)`)
- Test: `wuseradeTests/AppVersionTests.swift`

**Interfaces:**
- Consumes: `AccountManager`, the coordinators, `SignInError` (Task 11), `CatalogStore.meta?.minimumAppVersion` (Task 8).
- Produces: `enum AppVersion { static var current: String; static func isSupported(current: String, minimum: String?) -> Bool }` (numeric dot-separated compare).
- `AccountSection` behaviour:
  - Anonymous: shows a `SignInWithAppleButton`-styled button and a Google button, each running its coordinator and then `account.signIn(with:)`, plus one explanatory line.
  - Signed in: shows the provider and email, "Sign out", and "Delete account". Delete account opens a destructive `confirmationDialog`, runs the same provider's coordinator for re-authentication, then calls `account.deleteAccount(reauthWith:)`.
  - Errors: `SignInError.cancelled` is ignored silently. Other errors show an alert.
  - All new strings are Kabardian placeholders marked `// TODO(owner): copy`.

- [ ] **Step 1: Write failing tests:** `testNilMinimumIsSupported`, `testEqualIsSupported` ("1.5"/"1.5"), `testNumericCompare` ("1.5" vs "1.10" → false), `testNewerMajor` ("2.0" vs "1.10" → true), `testPatchAboveMinimum` ("1.5.1" vs "1.5" → true).
- [ ] **Step 2: Run** `-only-testing:WuseradeTests/AppVersionTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `AppVersion`, `UpdateRequiredView` (message plus a button opening `https://apple.co/3OWuu5b`), `AccountSection`, and the Settings and app wiring.
- [ ] **Step 4: Run** all `WuseradeTests` and the build. Expected: pass.
- [ ] **Step 5: Commit** `feat(ios): account settings, privacy link and minimum-version gate`

---

### Task 14: End-to-end verification and release checklist

- [ ] **Step 1: Device checks** (real device, signed with the team, prod Firebase), from the spec's Testing section:
  1. Fresh install → like 2 poems → Settings → Sign in with Apple → delete the app → reinstall → sign in with Apple → both likes are back.
  2. Repeat step 1 with Google.
  3. Second phone already signed in to the same Apple account. Like a poem anonymously, then sign in → the likes merge and nothing is lost.
  4. Delete account (Apple) → the Liked tab empties. In Firebase console, `users/{uid}` and the Auth user are gone. In Apple ID → Sign in with Apple, Wuserade is no longer listed.
  5. Install the current App Store version, like 3 poems, then update to this build → the 3 likes appear in the Liked tab and in `users/{uid}/likes`.
  6. Airplane mode after first launch: lists, search, the Liked tab and opening a liked poem all work.
  7. Set `meta/content.minimumAppVersion` above the build version → the update screen appears. Then remove the value.
- [ ] **Step 2: Run** all `WuseradeTests`, the rules tests (Task 1 command) and the admin tests (Task 3 command). Expected: all pass.
- [ ] **Step 3 (owner):**
  - Final `python -m wuserade_admin migrate && python -m wuserade_admin rebuild` just before submission, then freeze edits in Django admin.
  - In App Store Connect, set the Privacy Policy URL to `https://wuserade.com/privacy` and update App Privacy: contact info (email), identifiers (user ID), usage data, all linked to the user.
  - Submit the build. Keep Render running; shutting it down later is the owner's call.
