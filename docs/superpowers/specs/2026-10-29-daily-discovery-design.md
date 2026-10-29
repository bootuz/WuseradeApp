# Wuserade: daily discovery

Date: 2026-10-29
Status: approved by the owner on 2026-10-29

## Intent

Wuserade is an iOS app (iPhone and iPad, iOS 17+, SwiftUI, Firebase) for reading Kabardian
poetry. Its readers are fluent Kabardian speakers. The owner's problem: **the app feels empty.**
People open it without knowing what they want to read, and nothing in the app suggests where to
start, so a catalogue of about 4,100 poems feels like a handful. Home shows the day's poem, the
five newest poems and the themes. The other ways in (poets, themes, search) all assume the reader
already knows what to look for.

The data makes it worse:

- About 90% of poems have no theme (counted in the 2024 dump: 3,309 of 3,685). Browsing by theme
  reaches only a small part of the catalogue.
- No poet has a bio, so the Poets tab is a list of names.
- The five newest poems are all by one poet (checked 2026-10-29), so Home looks like one poet's page.

The owner wants readers to **find something worth reading without having to know what to look for,
and to come back every day.** Two decisions frame everything below:

- **Automatic, not editorial.** No one picks, writes or tags anything. Every feature runs on its own.
- **The server decides, the phone shows.** Picking poems, ranking suggestions and sending
  notifications are the server's job, not the device's. This includes moving today's day's poem,
  picked on the device by `DailyRotation`, to the server.

## Goals

The first version has five parts. The owner approved the mockups (see [Mockups](#mockups)).

1. **Home changes every day.** Under the day's poem, two new sections: **poet of the day** (portrait
   or initials, name, poem count, their three most-read poems, a link to all their poems) and **a
   short poem**, shown in full on Home.
2. **Widgets.** Home-screen widgets: medium (the day's poem, opening stanza) and small (the short
   poem of the day or the day's poem, the reader's choice). A lock-screen widget: the day's poem's
   title, poet and first line. Tapping any of them opens that poem in the app.
3. **A morning notification**, optional, with the day's poem: its title, poet and first lines. Off
   until the reader turns it on. The reader picks the time.
4. **Keep reading.** At the end of a poem, instead of today's single "next in the list" row: **more
   by this poet** (their most-read poems this reader hasn't read) and **you might also like** (other
   poems they haven't read).
5. **Reading history**, kept per account under `users/{uid}`, so suggestions skip what a reader has
   read and the history follows them to a new phone, like likes do.

The owner can see whether it works: Analytics events for opening each new surface (see
[Analytics](#analytics)).

## Non-goals (this phase)

- Readers' favourites: rankings from app-wide reading or like counts. "Most read" in this phase
  means the old website's view counts, which no longer change.
- A "surprise me" button.
- Automatically tagging the untagged poems with themes.
- A richer Poets tab (portraits, counts and first lines on every row).
- Poem pages on wuserade.com, or share links that open the app.
- Any editorial tool, or hand-overriding a day's pick.
- Personalised Home: Home's daily picks are the same for every reader.

## Anti-goals (would be a failure even if it works)

- **Streaks, counters, badges or any game-like nudging.** Wuserade is a quiet literary book. The pull
  comes from the poems. The owner ruled this out explicitly.
- Notifications a reader didn't ask for, or more than one a day.
- Requiring sign-in for anything here. Every reader has an account already (anonymous by default),
  and that is enough.
- The day's poem being different on Home, the widget and the notification on the same day.
- A Home that breaks or goes blank when the server is late or the phone is offline. Today's picks
  must still show from what was last loaded.
- A noticeable monthly bill under normal use (see [Cost](#cost)).
- Invented Kabardian. Every new label is an owner-copy slot (see [Owner copy](#owner-copy)).

## Constraints

- Firebase project `wuserade`. Firestore is in **europe-west3** (Frankfurt). The app already has
  Auth (anonymous, Apple, Google), Firestore, Analytics and Cloud Messaging (FCM). Storage for
  poet photos is in us-central1.
- **No Cloud Functions exist yet.** This is the project's first server code. It needs the **Blaze**
  plan, which the poet-photos Storage bucket already waits on. The Firebase migration spec said
  "no server code"; the owner has now chosen server work for this feature.
- Content is written only by the owner's admin tool (`firebase/admin`, Python 3.11,
  firebase-admin), run by hand. Content collections allow `get` by ID only, never `list` or queries
  (a query on `poems` would bill about 4,000 reads).
- The app reads the whole catalogue as a few `catalog/{n}` chunks (id, title, authorId, authorName,
  themeId, createdAt per poem) and `meta/content` (authors with poem counts and photo URLs, themes).
- **View counts were not migrated** to Firestore. They live in the old Django Postgres on Render
  (the admin tool's `migrate` reads it), and in the stale Feb 2024 `data.json` dump (3,685 poems; the
  live catalogue has about 4,100).
- The Xcode project syncs folders: every new top-level folder, and the new widget target, must be
  added to `project.pbxproj` (`PBXFileSystemSynchronizedRootGroup`).
- UI copy is Kabardian. The owner or a native speaker writes all new strings. Placeholders use
  `OwnerCopy` (`[owner copy: …]`).
- The design system is the "literary book" one: paper/night themes, Alegreya for content, SF Pro
  for chrome, bottle-green accent, gilt lozenge ornament.

## Approaches considered

- **A. Everything on the phone.** Extend `DailyRotation`: the date picks the poet and short poem on
  the device. The app writes two weeks of picks for the widget and schedules local notifications.
  No server, no Blaze. *Rejected by the owner:* picking and suggesting is the server's job, not the
  device's.
- **B. The server picks and pushes. Chosen.** Scheduled Cloud Functions write each day's picks to
  Firestore and send the morning notification to each reader at their chosen time. A callable
  function returns each reader's keep-reading suggestions from their reading history. Widgets,
  Home and notifications all read the same daily document. Costs: first Cloud Functions in the
  project, Blaze, and more to test and maintain. Gains: one source of truth, notifications that
  keep coming even if the app isn't opened, and the groundwork for readers' favourites later.
- **C. The admin tool writes a year's schedule.** `rebuild` writes a year of picks into one
  document. *Rejected:* someone must rerun it before the year runs out, which is the editorial
  upkeep the owner ruled out.

## Design

### Mockups

The owner approved one screen of mockups on 2026-10-29:
`.superpowers/brainstorm/63457-1793273302/content/daily-first-version.html` (git-ignored
brainstorm folder; open it in a browser). It shows, with real poems:

1. **Home:** the day's page as today, then *poet of the day* (initials circle, name, "452 [poems]",
   three titles, "all their poems ›"), then *a short poem* in full, then the new poems and themes.
2. **Home-screen widgets:** medium with the day's poem (head row with lozenge, label and date;
   title in small caps; poet; first stanza up to 4 lines); small with the short poem.
3. **Lock screen:** a rectangular widget (title · poet, first line) and the notification (app
   icon, "Wuserade", "<title> — <poet>", the first two lines). Settings rows: a toggle and a time.
4. **End of a poem:** the last stanza, lozenge, Like and Share, then *more by <poet>* (three rows)
   and *you might also like* (two rows, title and poet).

The mockups' caption under "Finishing a poem" says reading memory stays on the phone. That is out of
date: after seeing the mockups, the owner chose to keep reading history on the server, under
`users/{uid}` (see [Reading history](#reading-history-usersuidreadspoemid)). This document wins.

The mockups are a guide to layout and content, not pixels. Build with the existing design-system
components (`SectionLabel`, `PoemRowLabel`, `PoemTitleBlock`, `VerseView`, `PoetPortrait`/
`PoetInitials`, `Lozenge`).

### Data the server needs: line counts and view counts

The picking rules need each poem's **line count** (to find short poems and skip one-liners) and
**view count** (to rank "most read").

- The admin tool's `migrate` copies Django's `views` onto each `poems/{id}` document as `views: Int`
  (0 when unknown). If the Render Postgres is gone, take `views` from `data.json` for the poems it
  covers, and 0 for the rest.
- `rebuild` adds `lines: Int` (non-empty verse lines in `text`) and `views: Int` to every **catalog
  entry**, so the server ranks and filters from the few catalog chunks without reading 4,100 poem
  documents. The app's `PoemSummary` decoder ignores unknown keys, so old app versions are
  unaffected. (Builder's call: a separate server-only stats document instead, if catalog size
  matters. Two integers per entry is about 40 KB.)

### Daily picks: `daily/{date}`

A scheduled function, **`writeDailyPicks`**, runs once a day (europe-west3) and makes sure a
document exists for every date from yesterday to 7 days ahead. It writes only missing dates, so a
day's *picks* (which poem, which poet, which short poem) never change once written. With documents
prepared ahead, every reader's own "today", in any time zone, is ready.

**Corrections and removals.** The owner corrects or removes poems in the Firebase console and then
runs the admin tool's `rebuild`. `rebuild` also re-syncs the daily documents for yesterday through
the last written date:

- It refreshes the copied fields (`title`, `text`, `authorName`, the poet's `name`, `poemsCount`,
  `photoURL` and `topPoems` titles) from the current content.
- When a picked poem or poet no longer exists, it re-picks that slot for that date with the same
  rules.

Older dates are left alone. The picking code is shared between `rebuild` and `writeDailyPicks`. A
reader who already loaded today's document sees the change on their next Home refresh; that is
acceptable.

```
daily/{YYYY-MM-DD}            // the reader's local calendar date
  date: String                // "2026-10-29"
  poem:      { id, title, authorId, authorName, text }          // the day's poem
  shortPoem: { id, title, authorId, authorName, text }
  poet:      { id, name, poemsCount, photoURL?,                 // photoURL as in meta/content
               topPoems: [{ id, title }] }                      // three, most-read first
  createdAt: Timestamp
```

It holds everything Home, the widget and the notification need, so each needs **one read**.

Picking rules (the server keeps history by reading the previous `daily` documents it needs):

- **The day's poem:** any poem with at least 2 lines, not a day's poem in the last 365 days.
  Spread over the whole catalogue, not only the newest poems.
- **Poet of the day:** every poet with at least 3 poems appears once, in a shuffled order, before
  any poet repeats (a cycle). Not the poet of the day's poem or the short poem when it can be
  avoided. `topPoems` are their three highest-`views` poems (ties: newest first).
- **Short poem:** 2 to 9 lines. No repeat until every short poem has been used. Not the same poem
  as the day's poem.
- When it can be avoided, the three picks are by three different poets.
- The unknown-author placeholder ("Зытхар тщӀэкъым") is never a poet of the day. Its poems can still
  be the day's poem or short poem.

`firestore.rules`: `match /daily/{date} { allow get: if true; }`. Only the server writes it.

### Home

- `Library` loads `daily/{localDate}` through a new `DaysPoemSource`-style source, replacing
  `DailyRotation` (delete it and its UserDefaults keys). Keep the last loaded daily document on
  disk so Home shows today's picks offline. If today's document can't be loaded and nothing is
  cached, Home leaves the three daily sections out, as the day's page is left out today.
- Compact width (`HomeView`), top to bottom: the day's page (unchanged), *poet of the day*, *a
  short poem*, the new poems, the themes. The poet section's rows open the reader on that poem
  (paging through the three). The poet's name, portrait and "all their poems" open the poet's page.
  The short poem's title opens it in the reader.
- Regular width (`NewColumn`): today it lists the day's poem as one row under its label above the
  newest poems. Add the short poem as a row the same way, and the poet of the day as a name row
  that opens the poet. Builder's call on the exact arrangement, following the existing design.
- The day's poem is now the server's pick, so it changes once for readers who update.

### Reading history: `users/{uid}/reads/{poemId}`

```
users/{uid}/reads/{poemId}
  poemId: Int                 // == int(document ID)
  readAt: Timestamp           // the first time it counted as read
```

- **When a poem counts as read:** the reader has shown it for 10 seconds, or the reader scrolled to
  its end. Builder's call on the exact rule, but it must not count paging quickly past a poem. Opening
  it from a widget or notification counts the same.
- Written once per poem (create only), as the signed-in user, with the Firestore SDK's offline
  queue. A later read of the same poem writes nothing.
- Rules, like likes: the owner reads and deletes their own reads, and creates them with exactly
  `poemId` and `readAt`, where `poemId == int(readId)` and `readAt == request.time`. No update, no
  listing by anyone else.
- **Account flows**, which must match likes:
  - Deleting an account deletes its reads, before the user, as `deleteAccount` does for likes.
  - Signing in to an existing Apple/Google account from an anonymous one moves the anonymous
    reads into it, through the same pending-then-merge path as likes.
  - Linking keeps the uid, so reads stay.
- No reading-history screen in this phase. The history only steers suggestions.

### Keep reading: callable `keepReading`

The app calls **`keepReading(poemId)`** (a callable function, europe-west3) when a poem's reader
page opens. It returns:

```
{ poet:    [{ id, title }],                         // up to 3
  similar: [{ id, title, authorId, authorName }] }  // up to 2
```

- **More by this poet:** the poem's poet's poems, highest `views` first, excluding this poem and
  poems the caller has read.
- **You might also like**, first match wins, excluding this poem, the poet list above and read
  poems: (1) unread poems in the same theme, most-read first; (2) unread poems by poets the caller
  has liked (from `users/{uid}/likes`, the 50 most recent); (3) unread poems of similar length (±3
  lines) by other poets, most-read first.
- **Reads are cost-bounded.** The function keeps the catalog in memory per instance (re-read when
  `meta/content.catalogVersion` changes). It ranks candidates first, then checks only those
  candidates against the caller's reads with a batched get (at most about 25 documents). It never
  lists the whole history.
- Requires auth: every app user has an account, anonymous ones included.

In the reader: where `NextPoemRow` sits today, show *more by <poet>* and *you might also like*
when the result arrives. While it loads, or if it fails or the phone is offline, show today's
`NextPoemRow` (next in the list) where there is one. Never a spinner that blocks reading. A section
with no poems is left out.

### Morning notification

**On the phone:**

- Settings gets a section with a toggle (*morning poem*) and a time (default 08:00). Turning it on
  asks for notification permission if needed. If permission is denied, the toggle explains and
  links to iOS Settings.
- **One invitation:** on the reader's third distinct day of opening the app, Home shows a quiet,
  one-time invitation under the day's page, with *turn on* and *not now*. It never shows again
  after either choice or once the notification is on. No pop-up permission prompt at launch. (This
  replaces the launch-time `registerForRemoteNotifications` behaviour only in that permission is
  never asked unprompted. FCM registration itself can stay.)
- The app keeps a device document up to date when the toggle, time, time zone, FCM token or account
  changes:

```
users/{uid}/devices/{installId}   // installId: random, generated once per install
  fcmToken: String
  timeZone: String                // IANA, e.g. "Europe/Moscow"
  notifyAt: String                // "08:00", local time
  enabled: Bool
  nextSendAt: Timestamp           // the next UTC instant to send, computed from the three above
  updatedAt: Timestamp
```

- Signing out or deleting the account deletes this install's device document first. The new
  anonymous account registers again if the toggle is on.
- Rules: the owner creates, updates, reads and deletes their own device documents, with validated
  fields.

**On the server:** a scheduled function, **`sendMorningPoems`**, runs every 15 minutes. It runs a
collection-group query for devices with `enabled == true` and `nextSendAt <= now` (needs an index).
For each device it sends one FCM message with the day's poem from `daily/{date in the device's
time zone}`, then sets `nextSendAt` to the next day's `notifyAt` in that time zone, which handles
daylight-saving changes. Invalid tokens are deleted. So notification times are accurate to 15
minutes. That is the owner-facing trade-off of this design (builder's call: 5 minutes if cost
allows).

**The message:**

- Title: `<title> — <poet>`, or for an untitled poem `<first line> — <poet>`.
- Body: the first two lines.
- Data: `poemId` and `date`. Tapping opens the day's poem in the reader.
- No other wording, so no owner copy is needed in the message.

### Widgets

- A new **WidgetKit extension target**, with an App Group shared with the app. Families:
  `systemMedium` (the day's poem), `systemSmall` (a configuration intent chooses the short poem or
  the day's poem; default the short poem), `accessoryRectangular` (the day's poem's title, poet and
  first line).
- **Data:** the widget fetches `daily/{localDate}` directly over Firestore's REST API. The
  document is public, so no Firebase SDK is needed in the extension. It keeps the last document in
  the App Group as a fallback. Timeline: one entry now and one at the next local midnight. When the
  app loads a daily document it also writes it to the App Group and calls
  `WidgetCenter.shared.reloadAllTimelines()`.
- **Tapping** opens `wuserade://poem/{id}`. Handle it in the app's `onOpenURL` next to Google
  Sign-In's handler, and open the reader on that poem.
- The extension bundles Alegreya and uses the paper/night colour tokens, so widgets match the app.

### Owner copy

New `OwnerCopy` slots, which a native speaker writes:

- the poet of the day label;
- the short poem label;
- "all their poems";
- "more by" (followed by the poet's name);
- "you might also like";
- the Settings toggle and time labels;
- the denied-permission explanation;
- the invitation's text, plus *turn on* and *not now*;
- the widget gallery names and descriptions for each widget.

The poem count reuses `OwnerCopy.countNoun`. Localizations (English, Russian, Turkish, Arabic) follow
the existing `Localizable.xcstrings` workflow.

### Privacy

- **Privacy policy** (`firebase/hosting/privacy/index.html`): add *poems you have read* (poem ID and
  first-read time, under your account in Firestore, europe-west3, for suggestions, deleted with your
  account) and *notification settings* (time zone, chosen time, push token, under your account, to
  send the morning poem). The push token is already listed. Update "Last updated".
- **App Store privacy labels**: add Product Interaction (linked to the user, app functionality).
- **`PrivacyInfo.xcprivacy`**: add the matching collected data type.
- These must ship with, or before, the app version that writes reads.

### Analytics

Log through `AnalyticsManager`:

- `daily_open` with `source`: `home_poem`, `home_poet`, `home_short`, `widget`, `notification`;
- `keep_reading_open` with `section`: `poet` or `similar`;
- `morning_poem` with `enabled`: `true` or `false`;
- `invitation`: `accepted` or `dismissed`.

These let the owner see whether readers use the new ways in. No poem titles in event parameters.

### Cost

The target is to stay within the free allowances under normal use, with a budget alert on the Blaze
account. It costs:

- two scheduled jobs (within Cloud Scheduler's free three);
- one daily document per day;
- one read per Home load or widget refresh;
- at most about 25 reads per `keepReading` call;
- a 15-minute push job that reads only due devices.

The builder estimates monthly reads at the current audience size before launch and reports if
they exceed the free 50,000 reads a day.

### Server code layout

- `firebase/functions/`, **Python** 2nd-gen Cloud Functions (same language as the admin tool,
  and it can share the catalog and poem helpers). Region europe-west3.
- Wire it into `firebase.json`, with emulator support for tests.

Builder's call: TypeScript instead, if Python functions turn out to be a poor fit for scheduled
plus callable functions with FCM.

### Rollout

1. Admin tool: copy views, add `lines`/`views` to the catalog, rebuild.
2. Deploy rules (`daily`, `reads`, `devices`), the index, and the functions. Run
   `writeDailyPicks` once to fill yesterday through 7 days ahead.
3. Publish the privacy policy update.
4. Ship the app with the widget, and update the App Store privacy labels.

Old app versions keep their on-device day's poem. They have no widget or notification, so nothing
on one device disagrees with itself.

### Testing

- **Functions:** unit tests for the picking rules (cycles, no repeats, different poets, short
  bounds, unknown author), `nextSendAt` across time zones and daylight-saving changes, and
  `keepReading` ranking and filtering. Emulator tests that `writeDailyPicks` writes only missing
  dates and that `keepReading` respects the caller's reads.
- **Admin tool:** tests that `rebuild` refreshes copied fields in current and future daily
  documents, re-picks a slot whose poem or poet was removed, and leaves older dates alone.
- **Rules:** extend `firebase/rules-tests`: `daily` get-only, and `reads` and `devices` limited to
  their owner, with exact shapes.
- **App:**
  - unit tests for decoding the daily document;
  - the offline fallback;
  - the read-counting rule;
  - reads in account deletion and merge, alongside the likes tests;
  - the device document's `nextSendAt`;
  - the invitation's once-only logic;
  - the deep link.
- **Device check:** add each widget, receive a real notification at a chosen time, and tap through
  both.
- Note: on this Mac, port 8080 is taken by another program, so emulator suites need a temporary
  config with Firestore on another port.

## Left to the builder

- Exact read-counting rule (10 seconds or reaching the end is the intent).
- Catalog entries versus a separate stats document for `lines`/`views`.
- The regular-width arrangement of the new Home sections.
- How the reader shows suggestions arriving (no layout jump that moves what's being read).
- Push cadence (15 minutes or finer) and FCM batching.
- Python versus TypeScript for functions, if Python proves a poor fit.

## Calls made on the owner's behalf (please check)

- Home's daily picks are the same for every reader. Only keep reading is personal.
- The day's poem moves to the server and `DailyRotation` is removed.
- Daily documents are written a week ahead. Their picks never change, except that `rebuild` refreshes
  corrected text and re-picks a removed poem or poet for yesterday onward.
- Picking rules: no repeat day's poem within a year; poets cycle; short poems are 2–9 lines; three
  different poets when possible.
- The morning notification is off by default. One quiet invitation on the third day. Default time
  08:00, accurate to 15 minutes.
- A read counts after 10 seconds or reaching the end. No reading-history screen.
- The small widget can show the short poem or the day's poem (default: the short poem).
- Analytics events as listed, to judge whether it works.
- Python Cloud Functions in europe-west3. Free-tier target with a budget alert.
