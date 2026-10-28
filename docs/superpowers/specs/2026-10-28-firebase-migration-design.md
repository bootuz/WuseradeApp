# Wuserade: move to Firebase, add accounts

Date: 2026-10-28
Status: draft, awaiting approval

## Intent

Wuserade is an iOS app (iPhone and iPad, iOS 17+, SwiftUI) for reading Kabardian
poetry. Today it reads everything from a Django + Postgres server on Render
(`wuserade.onrender.com`). There are no user accounts, and liked poems live only in
SwiftData on the device.

The owner wants to **introduce accounts** so people keep their likes across devices
and so that, later, people can **submit their own poems**, which the owner reviews
before publishing. That is the reason for moving: the whole backend goes to
Firebase, and Render is retired.

The old React website is out of scope and goes offline at wuserade.com (its
Render service can be shut down later, the owner's call): the owner moves the
wuserade.com domain (apex and www) to Firebase Hosting, which serves a small home
page with the App Store link, and the privacy policy.

## Goals

- The iOS app reads all content (poems, authors, themes) from Firestore. The
  Django/Render backend is no longer needed by the new app version.
- Sign-in with **Apple**, **Google**, and **anonymous** accounts via Firebase Auth.
- Likes are stored per account in Firestore and sync across devices.
- **Account deletion** from inside the app (App Store guideline 5.1.1(v)).
- Search is at least as good as today: matches titles and author names, works
  with the different ways people type the palochka (Ӏ / I / l / 1).
- The data model leaves room for user-submitted poems and admin review, without
  building that feature now.
- Stays within Firebase's free allowance under normal use, on the Blaze plan with a
  budget alert. No server code.

## Non-goals (this phase)

- The website and its `/api/v1` API.
- The poem submission UI, the review queue, and any admin panel.
- View counters, like counters, and the daily featured poem. Django has these, but
  the app does not use them.
- Comments, following, or any social features.
- Changes to push notifications (FCM stays as is).

## Anti-goals (would be a failure even if it works)

- Requiring sign-in to read poems. Reading stays open to everyone.
- Anyone losing likes they already have on their phone.
- The app going blank for people who haven't updated yet, on the day the update ships.
- A recurring monthly server bill under normal use.
- An App Store rejection over sign-in or account deletion rules (4.8, 5.1.1(v),
  Sign in with Apple token revocation).

## Constraints

- Existing Firebase project **`wuserade`** is already in the app (Analytics,
  Messaging, `GoogleService-Info.plist`). Firestore is **not yet enabled** in it.
- Firebase iOS SDK via Swift Package Manager is already a dependency.
- Live data on Render (checked 2026-10-28): **4,091 poems, 14 themes**, about 36
  authors with poems. Poem text is plain text with `\r\n` line breaks. The
  `data.json` dump in the Django repo is from Feb 2024 and is **stale**, so
  don't migrate from it.
- The app identifies poems and authors by **Int IDs** (`Poem.id`, `Author.id`,
  `PersistedPoem.poemID`). These IDs are kept.
- UI copy is in Kabardian. The owner supplies the final wording for new strings.
- The only content admin is the owner.

## Approaches considered

1. **Firestore, search on the device (chosen).** Content lives in Firestore
   collections. The app downloads a small search list (poem id, title, author name;
   ~4k entries, a few hundred KB) and searches it locally. It runs on the free tier
   with no server code, uses Firestore's mature offline cache, and normalizes the
   palochka on device. Trade-offs: author/theme names are copied onto poems, and
   the search list must be rebuilt when content changes (by script).
2. **Firebase Data Connect / SQL Connect (Postgres).** This is the closest match to
   today's relational schema, and it has built-in server-side full-text search.
   Rejected because it needs the Blaze plan and an always-on Cloud SQL instance
   (from ~$9.40/month after a 3-month trial), it has more moving parts, and its
   search matches whole words rather than substrings like today.
3. **Firestore with server-side text search** (Enterprise text search, in Preview).
   Rejected: it's a preview feature and every search costs reads, which buys nothing
   at 4k poems.

The owner picked approach 1.

## Design

### Firebase setup

- **Firestore database:** the `(default)` database in project `wuserade`,
  **Standard edition**. Standard bills per document read, which suits the chunked
  catalog below; Enterprise bills per 4 KiB, so a 400 KB catalog would cost ~100
  units instead of a few reads. Standard also creates single-field indexes
  automatically. We don't need Enterprise pipelines or text search. Location:
  **`europe-west3` (Frankfurt)**, matching where Render runs today. *Owner's call
  to change; edition and location are permanent.*
- **Plan: Blaze** (owner's decision), with a budget alert set in Google Cloud
  Billing as part of setup. Blaze keeps the same free allowance as Spark but has no
  hard cap, so a traffic spike costs a little money instead of taking the app down.
  Nothing in this design uses Blaze-only features.
- **Read budget.** A typical visit should cost roughly 5–30 document reads:
  `meta/content` once, each poem opened, and the likes listener. The catalog is
  re-downloaded only when its version changes. Free-tier quota is 50,000 reads/day.
- **Auth providers:** Anonymous, Apple, Google.
- `firestore.rules`, `firestore.indexes.json` and `firebase.json` live in the iOS
  repo under `firebase/`, deployed with the Firebase CLI.

### Data model

IDs are the existing Django integer IDs, stored as string document IDs (`"4130"`)
and also as an `id` Int field so Swift `Codable` models keep `id: Int`.

```
poems/{poemId}
  id: Int
  title: String
  text: String              // plain text, as served today
  authorId: Int
  authorName: String        // denormalized
  themeId: Int?             // Django `category` FK; null if none
  createdAt: Timestamp
  updatedAt: Timestamp
  submittedBy: String?      // reserved: uid for future user poems; null for all migrated poems

authors/{authorId}
  id: Int
  name: String
  bio: String
  photoURL: String?         // Django `photo`; migrate the path, don't re-host images in this phase
  poemsCount: Int           // maintained by the admin script

themes/{themeId}
  id: Int
  title: String
  poemsCount: Int           // maintained by the admin script

catalog/{chunkId}           // e.g. "0", "1", ...; built by the admin script
  version: Int              // bumped on every rebuild
  entries: [{ id: Int, title: String, authorId: Int, authorName: String,
              themeId: Int?, createdAt: Timestamp }]

meta/content                // built by the admin script
  catalogVersion: Int
  catalogChunks: Int
  authors: [{ id: Int, name: String, poemsCount: Int }]   // only authors with poems
  themes:  [{ id: Int, title: String, poemsCount: Int }]
  nextPoemId: Int           // next free numeric ID for new poems
  minimumAppVersion: String? // see Rollout (or Remote Config, builder's call)

users/{uid}
  createdAt: Timestamp
  displayName: String?      // reserved for future poem attribution

users/{uid}/likes/{poemId}
  poemId: Int
  likedAt: Timestamp
  title: String             // snapshot so the Liked tab renders offline, like today
  authorId: Int
  authorName: String
  text: String
```

The Django `Poem.theme` CharField (the old hard-coded choices) is ignored. The app
uses `category` (the `Theme` FK). The Django `slug`, `views` and `likes` fields are
not migrated.

**Reserved for later (not built now):** `submissions/{id}` with `submittedBy`,
`title`, `text`, `status` (`pending|approved|rejected`), `createdAt`, `reviewedAt`.
On approval, the admin script copies the submission into `poems` with a new numeric
ID and `submittedBy` set. An `admin` custom claim on the owner's account will gate
any future in-app review screen.

### Security rules (intent)

- `poems`, `authors`, `themes`, `catalog`, `meta`: **anyone can read a document by
  its ID** (`get`); listing or querying a collection is denied, so one
  unauthenticated query can't bill thousands of reads. No client writes; content
  is written only via the Admin SDK.
- `users/{uid}` and `users/{uid}/likes/**`: read/write only when
  `request.auth.uid == uid`. Like documents are validated for shape (field types,
  `poemId` matches the doc ID).
- Everything else is denied.
- Rules are covered by tests against the Firestore emulator.

### Accounts and sign-in

- **Silent anonymous account.** On launch, if there is no Firebase user, the app
  calls `signInAnonymously()`. No UI. Reading works even if this fails (e.g.
  offline); liking waits until an account exists.
- **Upgrade, don't replace.** "Sign in with Apple" / "Sign in with Google" **link**
  the credential to the current anonymous user, so the uid and the likes stay the
  same.
- **Credential already in use** (the person already has an account, e.g. on a new
  phone): sign in to the existing account, copy the anonymous account's likes into
  it (merging, keeping the earliest `likedAt`), then delete the anonymous account's
  data and the anonymous user. The rules only let a user touch their own data, so
  order the steps accordingly: read the anonymous likes and clean up the anonymous
  account while still signed in as it, keeping a local copy until the merge write
  succeeds, so a failed step never loses likes.
- **Sign out:** signs out and immediately creates a new anonymous account. The Liked
  tab empties; the likes come back when the person signs in again.
- **Where it lives in the UI:** a new "Account" section at the top of the Settings
  sheet. Anonymous: Apple and Google sign-in buttons plus one line explaining that
  signing in keeps likes across devices. Signed in: provider and email (if any),
  Sign out, Delete account. No sign-in step is added to onboarding.
- Google Sign-In uses the `GoogleSignIn` SPM package. The Google provider must be
  enabled first, then `GoogleService-Info.plist` re-downloaded (for `CLIENT_ID` /
  `REVERSED_CLIENT_ID`) and the URL scheme added. Sign in with Apple needs the
  capability added to `Wuserade.entitlements`.
- Analytics: `Analytics.setUserID` uses the Firebase uid instead of the random UUID
  set in `TabBarView` today.

### Account deletion

Shown only for Apple or Google accounts.

1. Confirm with a destructive alert.
2. Re-authenticate with the same provider (Firebase requires a recent login to
   delete. For Apple, this also yields the authorization code needed to revoke).
3. Apple accounts: `Auth.auth().revokeToken(withAuthorizationCode:)`.
4. Delete `users/{uid}/likes/*` and `users/{uid}` (batched client-side).
5. `user.delete()`.
6. Clear local state, then start a fresh anonymous account.

If a step fails after data deletion, show an error and let the person retry. The
retry must be safe to run again.

### Moving existing on-device likes

On the first launch of the new version, once an account exists and a **per-device**
flag (UserDefaults) is not set, upload every `PersistedPoem` from SwiftData as a
like document (using its `persistedDate` as `likedAt`), then set the flag. The flag
is per device, not per account, so signing out or deleting the account never
re-uploads old local likes into the next anonymous account. After that, Firestore is the source of truth for likes and the Liked tab reads
from `users/{uid}/likes` (ordered by `likedAt` desc), relying on Firestore's offline
cache. The SwiftData store is left in place, unused, for one release, then removed.

### App data layer

Replace the URLSession `Endpoint`/`Service` layer with Firestore-backed services
that keep the existing view-model shapes, so views change as little as possible.

**Lists come from a cached catalog; full poems are read only when opened.** Some
authors have 300–450 poems, so querying `poems where authorId ==` would download
megabytes of text just to show titles and burn the read quota. Instead, the app
keeps the `catalog` (titles, authors, themes, dates for every poem) and
`meta/content` (author and theme lists) cached on disk, and builds every list screen
from them.

| Screen today | Today calls | New source |
|---|---|---|
| MainView → "Усэщlэхэр" (`PoemsListView`, the default home tab) | `/poems?page=N`, newest first | catalog sorted by `createdAt` desc; page on device (20 at a time, as today) |
| MainView → "Зытеухуар" (`CategoriesView`) | `/themes` | `meta/content.themes` |
| PoemCategoryView | `/themes/{id}/poems` | catalog filtered by `themeId` |
| AuthorsListView | `/authors/v2` | `meta/content.authors` (sorted on device with the existing Kabardian alphabet sort) |
| AuthorView | `/authors/{id}/poems` | catalog filtered by `authorId` |
| PoemView | `/poems/{id}` | `poems/{id}` (one read) |
| SearchView | `/poems/search?q=` | on-device search over the catalog |
| LikeButton / LikedPoemsView | SwiftData | `users/{uid}/likes` |

List rows that today show the poem text (if any) must switch to title + author.
The full text loads in `PoemView`. Only 433 of 4,091 poems currently have a theme;
that's expected.

`Poem.content` maps to Firestore `text`. `Author` keeps `id` + `name`.

### Search

- On launch, read `meta/content`. If `catalogVersion` differs from the cached
  version, fetch all `catalog` chunks and cache them to disk. Otherwise use the
  cache. On first launch with no network, lists show the normal offline/empty state.
- Normalize both the query and the entries: lowercase, then map the palochka
  variants `Ӏ ӏ I i l 1` to a single character (note that `I` lowercases to `i`),
  and trim whitespace.
- Match when the normalized query is a substring of the normalized title or author
  name (today's behaviour). Search as the person types instead of on submit; ranking
  (title prefix first) is the builder's call.
- Tapping a result opens `PoemView(poemID:)` as today.
- Chunk size: keep each chunk well under Firestore's 1 MiB document limit (e.g. 2,000
  entries per chunk).

### Admin tooling (owner only)

A small Python tool in `firebase/admin/` that uses the Firebase Admin SDK with a
service-account key kept outside the repo:

- **`migrate`**: reads the live Render Postgres (via `DATABASE_URL` from the Render
  dashboard) and upserts `themes`, `authors`, `poems` by ID. It's safe to re-run,
  so it can run again just before release to pick up late edits. Afterwards it
  recomputes counts, rebuilds `catalog`, sets `meta/content` (including
  `nextPoemId = max(id) + 1`), and prints a check: document counts vs Postgres
  counts.
- **`add-poem`**: adds a poem from a text file plus author/theme IDs, assigns
  `nextPoemId`, updates counts, and rebuilds the catalog.
- **`rebuild`**: recomputes counts, the catalog and `meta/content` after any manual
  edit in the Firebase console.

Day-to-day edits to existing poems can be made in the Firebase console, followed by
`rebuild`.

### Privacy policy (hosted page)

The app has no privacy policy link today, and accounts make one mandatory in-app
(guideline 5.1.1(i)). The owner chose to have one drafted and hosted on Firebase
Hosting.

- A single static page under `firebase/hosting/` (e.g. `privacy/index.html`),
  served at `https://wuserade.com/privacy` (also reachable at
  `https://wuserade.web.app/privacy`). `www.wuserade.com` redirects to the apex.
- The builder drafts it in English, from what the app actually collects:
  - Firebase Auth: uid, plus the email and name Apple/Google share (Apple may relay
    a private email).
  - Likes stored per account.
  - Firebase Analytics usage data, now tied to the uid.
  - The FCM token for push notifications.
  - How to delete the account in-app, and what deletion removes.
  - Contact: the email already listed in Settings.
  The owner reviews the text, and can add a Kabardian or Russian version.
- Settings gets a "Privacy policy" link (shown to everyone, not only signed-in
  users).
- Release checklist: set the URL in App Store Connect and update the App Privacy
  answers (contact info, identifiers and usage data, linked to the user).

### Rollout

1. Enable Firestore and the auth providers, set the budget alert, deploy rules,
   indexes and the privacy page, and run `migrate`.
2. Ship the new app version with a **minimum-version check**, so future breaking
   changes can show an "update the app" screen. Old versions can't
   be gated this way; they don't have the check.
3. Keep Render running unchanged so older versions keep working. Freeze content
   edits in Django admin after the final `migrate` run.
4. When the owner decides adoption is high enough (App Store Connect version stats),
   shut Render down. *Owner's call on timing.*

### Testing

- Firestore rules tests against the emulator (own likes allowed, others' denied,
  content read-only).
- Unit tests for search normalization and matching, including palochka variants and
  mixed case.
- Unit tests for the anonymous-to-existing-account likes merge.
- Migration check: counts match Postgres, and spot-check a sample of poems by ID.
- Manual on device: fresh install → like → sign in with Apple → reinstall → sign in
  → likes are back; repeat with Google; delete account; upgrade from the App Store
  version with local likes → likes are uploaded.

## Left to the builder

- Exact Swift type and file structure for the new Firestore services, and whether
  to keep the generic `Service` protocol shape.
- Bumping the Firebase iOS SDK (currently 10.22.1) to a current release and adding
  `FirebaseAuth`, `FirebaseFirestore` and `GoogleSignIn`.
- Where the minimum-version value lives (`meta/content` or Remote Config).
- Search ranking and debounce details.
- Composite indexes needed for the queries above.
- Placeholder Kabardian strings for new UI, marked for the owner to replace.
- Whether `firebase/admin/` uses a CLI framework or plain argparse.

## Calls made on the owner's behalf (please check)

- Standard edition, `europe-west3` location.
- List screens built from a cached catalog; full poem text loaded on open.
- Privacy policy drafted in English, served at `wuserade.com/privacy`.
- Silent anonymous account on launch; sign-in lives in Settings, not onboarding.
- Like documents store a snapshot of the poem (so the Liked tab works offline, as
  today).
- Sign out → fresh anonymous account with empty likes.
- Delete account offered only for Apple/Google accounts.
- Featured poem, view counts and like counts dropped.
- Admin tooling lives in this repo under `firebase/admin/`.
- Minimum-version check added.
