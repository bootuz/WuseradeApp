# Wuserade: poet photos sent by readers

Date: 2026-10-28
Status: approved by the owner on 2026-10-28
Builds on: `main` at `64634e5` (the redesign merged with the Firebase migration), the
Firebase spec (`2026-10-28-firebase-migration-design.md`) and the redesign handoff
(https://claude.ai/artifact/277Z4QNsybq98geUrVTpjd)

## Intent

The poet page shows the poet's name, the poem count and the poems. The owner wants each
poet to have a photo. None of the 36 poets has one, so readers will help fill them in.
A reader signed in with Apple or Google can send a photo for a poet. The owner approves
it, and only then does it appear.

Two things follow. First, the page has to look finished without a photo, because that
is what every reader sees at first. Second, taking photos from readers makes the app one
with user-generated content, so App Store guideline 1.2 applies: filtering, reporting,
blocking, and published contact details.

## Goals

- The poet page shows a round portrait centred above the name and the poem count. With
  no photo, the circle shows the poet's initials.
- If the poet has no approved photo, a button under the count lets a reader send one.
  Once a photo is approved, the photo shows and the button is gone, for everyone.
- Only readers signed in with Apple or Google can send. An anonymous reader who taps the
  button gets a sheet with two options: Sign in with Apple, and Google.
- A reader sends only the photo. Nothing else is asked for.
- Photos go to Firebase Storage and wait there until the owner approves or rejects them
  with a command on the Mac.
- Guideline 1.2 is met:
  - **Filtering:** the owner's approval.
  - **Rights:** a line telling readers to send only photos they have the right to share.
  - **Reporting:** "Report this photo" on every approved photo.
  - **Blocking:** an admin command that blocks a sender.
  - **Contact details:** already in Settings.

## Non-goals (this phase)

- An in-app review screen for the owner.
- Cropping in the app, a photo credit or source, a caption, or the poet's bio.
- Telling the sender when their photo is approved or rejected.
- Photos anywhere except the poet page (not in the poets list, the reader or search).
- Firebase App Check.
- First lines under titles on the poet page. Catalog entries carry no poem text; adding
  them is separate work.

## Anti-goals (would be a failure even if it works)

- Any photo shown to readers before the owner approves it.
- A sign-in prompt anywhere except when a reader taps the send button. Reading stays
  open to everyone.
- A photo's location or other metadata reaching Storage.
- An App Store rejection over guideline 1.2, 4.8, 5.1.1(i) or 5.1.1(v).
- A later `migrate` or `rebuild` run wiping approved photos.
- A recurring monthly bill under normal use.

## Constraints

- iOS 17.0 deployment target stays. Newer APIs only behind `if #available`.
- No new third-party Swift packages. The Firebase iOS SDK gains the `FirebaseStorage`
  product. The admin tool may add Pillow for resizing.
- Accounts, likes and content already work on `main`. See `AccountManager`,
  `LikesController`, `CatalogStore`, `Library`, `firebase/firestore.rules` and
  `firebase/admin/wuserade_admin`. Extend them; don't copy them.
- Content rules allow `get` only, never `list`. New collections follow the same
  approach: the app reads documents by known ID.
- The Storage bucket `wuserade.firebasestorage.app` (named in
  `GoogleService-Info.plist`) doesn't exist yet. It will be created in **us-central1**,
  the region where Firebase's free storage allowance applies. The location is permanent.
- New Kabardian strings are `[owner copy: …]` slots in `OwnerCopy`. Never invent
  Kabardian. Write the palochka as U+04C0.
- Follow the design system's rules: `Palette` tokens, Alegreya through `.serif(_:)`,
  `CapsuleButtonStyle`, no focus rings, and system chrome left to the system.

## Approaches considered

1. **Sign-in plus Firebase Storage, approved from the Mac (chosen).** Accounts already
   exist on `main`. Uploads go to Storage, a Firestore record marks each waiting photo,
   and the owner approves with new `photos` commands in the existing admin tool.
2. **The same, but approved inside the app.** An owner-only review screen with approve,
   reject and crop. It adds a screen, admin rules and a crop control.
3. **The screen now, sending later.** Least work, but no photos come in until later.

Ruled out:
- Storing uploads in Django: Render wipes its disk on every deploy.
- Approving by hand in the Firebase console: the console has no approve action.

The owner picked approach 1, the free US region for the bucket, and all three of the
1.2 additions.

## Design

### The poet page

Sketch: "Round portrait, centred", the initials version.

From top to bottom, centred in the reading margin:

1. **The portrait,** a 128 pt circle.
   - **No photo:** `accentWash` fill with the initials in Alegreya Medium, `accent`, about
     44 pt. It is decorative (`accessibilityHidden`).
   - **Photo:** the photo fills the circle (`scaledToFill`, centred), with a 1 pt
     `hairline` ring. It is an accessible image labelled
     `[owner copy: photo of the poet]`, with a context menu holding
     `[owner copy: report this photo]`. VoiceOver reaches it through the actions rotor.
   - **Photo still loading, or failed to load:** initials, so the page never shows an
     empty hole. The photo fades in when it arrives, with no fade under Reduce Motion.
2. **The name** in `.serif(.headerTitle)`, `ink`, marked as a header, `Space.six` below
   the circle.
3. **The count line:** `\(count) \(OwnerCopy.countNoun)` in `.serif(.sectionLabel)`,
   `inkSecondary`, `Space.two` below the name.
4. **The send area,** `Space.four` below the count. Exactly one of these shows:
   - **The button:** `[owner copy: send a photo]` with `.secondaryCapsule`. It shows when
     the poet has no approved photo, and this reader isn't known to have one waiting
     for that poet. It also shows to anonymous readers.
   - **The waiting line:** `[owner copy: photo sent, waiting for review]` in
     `.serif(.rowSubtitle)`, `inkSecondary`. It shows when this reader's own waiting
     record exists.
   - **Nothing:** when the poet has a photo, or when the waiting check failed offline.
5. **The poem list,** as today.

This replaces `DetailHeader` on the poet page only. The theme page keeps
`DetailHeader`.

**The unknown-author poet** ("Зытхар тщӀэкъым", id 99) keeps the plain `DetailHeader`:
no circle and no button. Recognise it the same way `PoetsView` already sets it apart.

**Initials** are the first Kabardian letter of each of the first two words of the name,
from `KabardianAlphabet.sectionLetter(of:)`. That way Хь, Къ, Кхъ and the like count as
one letter. A one-word name gives one letter.

**iPad:** the same page in the content column, centred in it.

### Sending a photo

1. The reader taps the button.
2. **If the account isn't `.signedIn`** (anonymous, or none yet), present the sign-in
   sheet below. When the state becomes `.signedIn`, dismiss the sheet and go on to
   step 3 straight away. On cancel, nothing else happens.
3. Present the system photo picker:
   `.photosPicker(isPresented:selection:matching: .images)`. No photo-library permission
   is needed or requested.
4. Prepare the image with ImageIO:
   - Use `CGImageSourceCreateThumbnailAtIndex` with
     `kCGImageSourceCreateThumbnailWithTransform` and a maximum pixel size of 2,000.
   - Encode it as JPEG at about 0.85 quality.
   - Write **no metadata**: no location, no camera data.
5. **The send sheet** (a medium-detent sheet, a form sheet on iPad):
   - The prepared photo in the same 128 pt circle, so the reader sees what will show.
   - The poet's name.
   - The rights line `[owner copy: send only photos you have the right to share]` in
     `.serif(.prose)`, `inkSecondary`.
   - `[owner copy: send]` with `.primaryCapsule(fullWidth: true)`, and the app's
     `CloseButton`.
6. While sending, the button shows progress and is disabled.
7. Upload to Storage at `photo-submissions/{authorId}/{uid}.jpg` with content type
   `image/jpeg`. Then write the record `photoSubmissions/{authorId}_{uid}`.
8. **On success:** dismiss the sheet. The page shows the waiting line, and an
   announcement reads its text.
9. **On failure:** the sheet stays, with `[owner copy: photo could not be sent, try again]`
   above the button.
10. **If the reader is blocked**, the rules refuse the upload. Show
    `[owner copy: this account can't send photos]` instead, and don't offer a retry.

Sending again for the same poet, after a rejection, overwrites the earlier file and
record. So each reader has at most one waiting photo per poet.

### The sign-in sheet

A sheet with the medium detent (a form sheet on iPad), the grabber, and `CloseButton`:

- **Title:** `[owner copy: sign in to send a photo]` in `.serif(.emptyTitle)`.
- **Note:** `[owner copy: why sending needs an account]` in footnote, `inkSecondary`.
- **Buttons:** the same Apple and Google buttons as Settings' Account section. Move
  them out of `AccountSection.swift` into a shared view, `SignInButtons`, and run the
  same flow: the coordinator, then `account.signIn(with:)`, then the same alerts.
  Signing in links the anonymous account, so the uid and likes carry over. If that
  Apple or Google account already exists, it is used instead and the likes are merged,
  as `AccountManager` already does.

### What the app reads

- **Approved photos** come with the poet list the app already caches.
  `meta/content.authors[]` gains `photoURL: String?`, and `AuthorEntry` decodes it with
  `decodeIfPresent`. Older builds ignore the extra key. The poet page needs no extra read
  to know whether a photo exists, and the answer is there offline.
- **This reader's waiting photo:** for a signed-in reader on a poet without a photo,
  one `get` of `photoSubmissions/{authorId}_{uid}`. Firestore's offline cache answers
  repeat visits.
- **Library:** add `photoURL(ofPoet:) -> URL?`. Put the waiting check in a small new
  observable, `PhotoSubmissions`, with `isWaiting(poetID:)`, `send(_:for:)` and
  `deleteAll(uid:)`, provided through the environment like `LikesController`.
- **Image loading:** from `photoURL`, with a disk cache that lasts across launches. The
  builder picks the mechanism; a `URLCache` with a disk size is enough.

### Data model

Firestore:

```
authors/{authorId}
  photoURL: String?            // the existing field: the approved photo's download URL, or null

meta/content
  authors: [{ id, name, poemsCount, photoURL? }]   // photoURL added; omitted or null when none

photoSubmissions/{authorId}_{uid}   // one per reader per poet; exists only while waiting
  authorId: Int
  submittedBy: String               // uid
  createdAt: Timestamp              // request.time
```

Storage, bucket `wuserade.firebasestorage.app` in us-central1:

```
photo-submissions/{authorId}/{uid}.jpg   // waiting; only the sender and the admin tool can read it
poets/{authorId}.jpg                     // approved; public through its download URL
```

Approving or rejecting deletes the submission record and its file. The app shows the
waiting line while the reader's record exists, and the button again once it is gone.
Nothing records who sent an approved photo.

**Blocking** is a custom claim, `photoBan: true`, set by the admin tool on the sender's
account. Both rule sets check the claim, so it costs no reads. The block takes effect
when the sender's token refreshes, within an hour. The ban command also revokes the
sender's refresh tokens, so the next refresh fails and the sender must sign in again,
which picks up the claim. A token already issued keeps working until it expires, so the
block is not instant.

### Security rules (intent)

**`firebase/firestore.rules`** keeps everything it has and adds:

- **`photoSubmissions/{id}`:**
  - **Create or overwrite** only by a reader who is signed in with
    `sign_in_provider` in `['apple.com', 'google.com']` and has no `photoBan` claim.
    The `id` must be `string(authorId) + '_' + uid`, `submittedBy == uid`, and
    `createdAt == request.time`. The record must have exactly the three fields, with
    the right types.
  - **Get and delete** only by the reader whose uid ends the `id`. The check must work
    when the record doesn't exist, so it tests the document ID, never
    `resource.data`. Otherwise a reader with nothing waiting gets "permission denied"
    instead of "not found".
  - **List:** never.
- **`authors`** and **`meta`:** unchanged. Content stays read-only for clients.

**`firebase/storage.rules`** is new. Register it in `firebase.json` together with a
Storage emulator port:

- **`photo-submissions/{authorId}/{uid}.jpg`:**
  - **Write** under the same sign-in and claim test, only to the reader's own `{uid}`,
    only `image/jpeg`, and only up to 5 MB.
  - **Read and delete** only by that reader.
- **`poets/{file}`:** no client writes. Reads go through the download URL.
- **Everything else:** denied.

Tests in `firebase/rules-tests` cover every allow and deny above, including:
- anonymous tokens, and tokens with the claim, being refused;
- reading a missing record being allowed for its owner.

### Approving and blocking (owner, on the Mac)

New `photos` commands in `wuserade_admin` (credentials and emulator handling as the tool
already does):

- **`photos list`:**
  - Downloads every waiting photo into `~/Downloads/wuserade-photos/` as
    `{authorId}-{poet name}-{uid prefix}.jpg`.
  - Prints one line per photo: the submission ID, the poet and the date.
  - Poet names come from `authors/{id}`.
- **`photos approve <submissionId> [--file edited.jpg]`:**
  - Publishes the photo, or the owner's cropped copy given with `--file`, to
    `poets/{authorId}.jpg`. It is resized so its long side is at most 1,024 px.
  - Sets `authors/{id}.photoURL` to its download URL.
  - Updates the matching entry in `meta/content.authors` in the same transaction,
    without rebuilding the catalog, so apps don't download the catalog again.
  - Deletes every waiting submission for that poet, records and files.
  - Approving a photo for a poet who already has one replaces it.
- **`photos reject <submissionId>`:** deletes that record and its file.
- **`photos remove <authorId>`:** takes an approved photo down by clearing `photoURL` in
  both places and deleting `poets/{authorId}.jpg`. This is the response to a report.
- **`photos ban <uid>`:**
  - Sets the `photoBan` claim and revokes the sender's refresh tokens.
  - Deletes their waiting submissions.
  - The submission ID gives the uid.
- **`photos unban <uid>`:** removes the claim.

**Changes the existing commands need:**
- `rebuild`'s `meta_document` copies each author's `photoURL` into `meta/content.authors`.
- `migrate`'s `upsert_content` must never clear a `photoURL` that is already set.
  Django's `photo` is empty for every poet, so either leave the field out when Django's
  value is blank and write authors with merge, or keep the stored value.
- Tests against the emulators cover all of this.

The owner crops a photo in any image editor before approving it with `--file`, if
needed. The circle shows the centre of the photo.

### Reports

**"Report this photo"** opens a mail to the owner (`AppLinks.email`).
- **Subject:** `[owner copy: photo report]` with the poet's name and ID.
- **Body:** the poet's ID only.

The owner answers a report with `photos remove`, and with `photos ban` if the sender
should be blocked. The App Review notes should say how reports are handled.

### Account deletion

`AccountManager.performDeleteAccount` gains one step, after `likes.deleteAllData(uid:)`
and before `deleteCurrentUser`. It deletes the reader's waiting photos through
`PhotoSubmissions.deleteAll(uid:)`:
- Each waiting record is found by its known ID, `{authorId}_{uid}` for every poet in
  `meta`, because the rules forbid listing.
- For each one, the file is deleted first, then the record.
- The step must be safe to run again.

The delete warning gains `[owner copy: photos you sent that are still waiting are deleted
too]`. Approved photos stay on the poet's page, linked to nobody.

### Privacy policy

`firebase/hosting/privacy/index.html` gains a photos section:
- **What happens to a photo:**
  - Photos a reader sends are stored in Firebase Storage in the United States
    (us-central1) until the owner reviews them.
  - An approved photo is published on the poet's page and isn't linked to the sender.
    A rejected one is deleted.
  - Location and camera data are removed before upload.
- **Account deletion** deletes photos still waiting, and approved photos stay.
- **A blocked account** can't send photos.
- **Location sentence:** the page's line on where data is stored changes from "likes are
  stored in Frankfurt" to cover both places.

The owner reviews the wording before it's deployed.

**Release checklist:**
- App Privacy answers: photos (user content), linked to the user while waiting.
- App Review notes: the review, report and block process.

### Owner setup

1. **Storage bucket:** in the Firebase console, create the default bucket in
   **us-central1** (the project must be on Blaze).
2. **Google's G:** download the official mark from Google's branding guidelines and add
   it to the asset catalogue. The Google button shows it, in Settings and in the sheet.
3. **Copy:** write the new `[owner copy: …]` strings.

The builder deploys the rules and the privacy page after the owner says go.

### Testing

- **Rules:** tests against the Firestore and Storage emulators, as listed above.
- **Swift unit tests:**
  - Initials: one word, two words, Хь and Кхъ at the start, extra spaces.
  - Image preparation: long side at most 2,000 px, no GPS or EXIF in the output,
    orientation applied.
  - The send area's state for each combination: photo present, waiting record,
    anonymous or signed in, waiting check failed.
  - `AuthorEntry` decoding with and without `photoURL`.
  - The new deletion step, using the existing fakes.
- **Admin tool tests against the emulators:**
  - approve publishes and updates both places, and clears every waiting submission for
    that poet;
  - reject, remove, ban and unban;
  - `rebuild` keeps photos;
  - `migrate` doesn't clear them.
- **On a simulator or device:**
  1. As an anonymous reader, tap the button, sign in with Apple, pick a photo, see it in
     the send sheet, send it, and see the waiting line.
  2. Approve it from the Mac: the photo appears and the button is gone for everyone.
  3. Report it: Mail opens.
  4. Reject a second photo: the button comes back.
  5. Ban a test account: sending is refused.
  6. Delete the account: its waiting photos are gone.
  7. Check night mode, accessibility text sizes and iPad.

## Left to the builder

- The view and file structure of the poet header, the send sheet and `SignInButtons`,
  within the redesign's feature folders.
- The image cache mechanism and size, and the upload progress style.
- How the admin tool lays out its `photos` subcommands, and the test setup.
- Whether `PhotoSubmissions` reads with `getDocument(source: .default)` or a listener.

## Calls made on the owner's behalf (please check)

- After signing in from the sheet, the photo picker opens straight away.
- **New step:** a send sheet after the picker shows the photo in the circle with the
  rights line and a Send button. I added it so the rights line is seen before every
  send, and so readers see the crop.
- No crop step in the app. The photo is shrunk to 2,000 px and stripped of metadata.
  The owner crops before approving if needed, and approved photos are published at up
  to 1,024 px.
- The waiting line replaces the button only for the sender. Approving one photo deletes
  the others for that poet. Rejecting brings the button back. One waiting photo per
  reader per poet.
- Initials: the first letters of the first two words, counting Kabardian multi-letter
  letters as one.
- The unknown-author page gets no circle and no button.
- Approved photos live in `authors/{id}.photoURL` and `meta/content.authors[].photoURL`,
  so the app needs no extra read. Approving updates `meta` without a catalog rebuild.
- Reporting opens a mail to the owner. Blocking is a custom claim, so no rule reads it
  from Firestore.
- Approved photos stay after the sender deletes their account, linked to nobody.
- No App Check for now.
