# Wuserade Cloud Functions

The server side of the daily discovery: the day's picks, the morning poem and the suggestions at
the end of a poem. Python, 2nd-gen Cloud Functions, in `europe-west3` (Frankfurt), next to Firestore.

| Function | Kind | When it runs | What it does |
|---|---|---|---|
| `writeDailyPicks` | scheduled | every day at 00:10 UTC | Writes `daily/{date}` for every date from yesterday to 7 days ahead that has no document yet. A written day never changes, except through the admin tool's `rebuild`. |
| `sendMorningPoems` | scheduled | every 15 minutes | Finds the devices whose morning time has come, sends each the day's poem in its own time zone, and sets its next time. Deletes devices whose push token is dead. |
| `keepReading` | callable | when a poem opens in the reader | Returns up to 3 more poems by the same poet and up to 2 others the reader might like, leaving out poems the reader has read. Needs a signed-in user (anonymous is fine). |

The code:

- `main.py` declares the three functions.
- `wuserade_daily/` holds the rules: `picks.py` (which poem, short poem and poet), `daily.py` (the daily
  documents), `morning.py` (send times and the message), `keep_reading.py` (suggestions).
- The admin tool imports `wuserade_daily` too, so `rebuild` re-picks with the same rules.

## Setup

Needs Python 3.12, the runtime the functions use in the cloud. Firebase looks for the virtual
environment in a folder called exactly `venv`, both to deploy and for the emulator:

```sh
cd firebase/functions
python3.12 -m venv venv
venv/bin/pip install -r requirements.txt
venv/bin/pip install -e '.[dev]'
```

`venv` is git-ignored and is not uploaded when you deploy (see `ignore` in `firebase.json`).

## Tests

The rule tests run anywhere:

```sh
cd firebase/functions
venv/bin/python -m pytest -q -m "not emulator"
```

The rest need the Firestore emulator and only ever use project `demo-wuserade`. Run everything from
`firebase/`:

```sh
cd firebase
npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore,storage,auth \
  "cd functions && venv/bin/python -m pytest -q"
```

On a Mac where port 8080 is taken, add `--config firebase.test.json` (the same file with Firestore on
port 8085; it is git-ignored).

To try the whole thing by hand, start the emulators with the functions too:

```sh
npx -y firebase-tools@latest emulators:start --config firebase.test.json --project demo-wuserade \
  --only firestore,auth,functions,storage
```

Then fill them with the admin tool (`FIRESTORE_EMULATOR_HOST=127.0.0.1:8085`, see its README). The
emulator serves `keepReading`, but does not run the two scheduled functions; call
`write_missing_days` and `send_due` from a short Python script instead. A debug build of the app
started with the launch argument `-useEmulators` talks to these emulators instead of production
(Auth 9099, Firestore 8085, Functions 5001, Storage 9199). It starts signed out, switches Analytics
off for that install until the next normal launch, and asks for no push token.

## Deploying (owner)

In this order. Every step is yours; nothing here has been deployed.

1. **Blaze plan, with a budget alert.** Scheduled functions need the Blaze (pay as you go) plan. In the
   Google Cloud console, under Billing > Budgets & alerts, set a small monthly budget (for example
   $5) with email alerts at 50%, 90% and 100%.
2. **View counts.** From `firebase/admin`, run `views --dsn URL`, or `views --json data.json` if the
   old Postgres is gone. It ends with a `rebuild`, so the catalog carries `lines` and `views`.
3. **Rules, index and functions:**
   ```sh
   cd firebase
   firebase deploy --only firestore:rules,firestore:indexes,functions
   ```
   The `devices` index can take a few minutes to build. `sendMorningPoems` fails until it is ready.
4. **Fill the days.** In the Google Cloud console, under Cloud Scheduler, find the job for
   `writeDailyPicks` and choose *Force run* once. It writes yesterday to 7 days ahead. Check that
   `daily/{today}` exists in Firestore.
5. **Privacy page:**
   ```sh
   firebase deploy --only hosting
   ```
   Fill in `[owner copy: release date]` in `hosting/privacy/index.html` first.
6. **Ship the app,** and update the App Store privacy labels: Product Interaction, linked to the user,
   for app functionality. See also the Device ID question in the checklist below.

## What it costs

Firestore's free tier allows 50,000 document reads a day. These are the reads the daily discovery adds,
counted from the code, for D daily active users (DAU):

| Source | Reads | How it is counted |
|---|---|---|
| Home | 1.5 × D | One read of `daily/{today}` per device per day (later opens use the cached day), plus pull-to-refresh, guessed at 0.5 a day. |
| Widgets | 0.75 × D | One read per widget kind per refresh: at midnight, and when the app saves a new day. Guessed: a quarter of readers have a widget, 1.5 kinds each, 2 refreshes a day. A failed refresh retries within the hour, so a phone offline all day can add up to 24. |
| `keepReading` | c × q × D | c calls per reader per day, q reads per call (below). |
| `sendMorningPoems` | 96 + E + up to 192 | 96 runs a day, each a query that costs at least 1 read; 1 read per device it sends to (E devices with the morning poem on, guessed at 0.3 × D); 1 read of the day's document per date per run that sends. |
| `writeDailyPicks` | up to about 380 | `meta/content` and the catalog chunks (4), the 9 days it checks, the history of up to 365 earlier days for the one new day, and 2 poem texts. |
| Sign-in to an existing account, account deletion | rare | Lists the reader's reads and likes once. |

**Reads per `keepReading` call (q).** 1 read of `meta/content` (the catalog itself stays in memory),
then one batched check of the ranked candidates against the reader's history: 10 by the same poet
and 5 of similar length, plus 5 in the same theme, or else 5 by liked poets. A missing document
still counts as a read. When the theme has fewer than 5 other poems, it also reads the reader's 20
latest likes (at least 1 read). So q is 21 for a poem in a well-filled theme, and at most
1 + 25 + 20 = 46.

**Calls per reader (c).** One call per reader page that loads. The reader pages through a list and
prepares the pages next to the one shown, which call too. For a reader who reads 5 poems a day in one
sitting, c is about 5 + 2 = 7.

So, with the guesses above:

```
reads a day ≈ D × (1.5 + 0.75 + 7 × q + 0.3) + 670
            ≈ 150 × D + 670   (q = 21, typical)
            ≈ 325 × D + 670   (q = 46, worst case)
```

| DAU | Typical (q = 21) | Worst case (q = 46) |
|---:|---:|---:|
| 100 | 15,600 | 33,100 |
| 500 | 75,400 | 163,000 |
| 1,000 | 150,200 | 325,200 |
| 5,000 | 748,400 | 1,623,400 |

**The free 50,000 reads a day are used up at about 330 DAU typically, and at about 150 DAU in the
worst case.** `keepReading` is over 95% of it. Above that, reads cost roughly $0.04 to $0.06 per
100,000 (check today's price for europe-west3): at 1,000 DAU about $1 to $5 a month, at 5,000 DAU
about $8 to $28 a month.

Not counted above: the app's existing reads (`meta/content` at each launch, one read per poem page
loaded, the likes list), which use the same 50,000. Writes are within the free 20,000 a day up to
about 3,800 DAU (about 5 new reads written per reader a day, plus device updates). Function calls
are within the free 2 million a month up to about 9,500 DAU.

These are estimates from the code and the guesses named above, not measurements. After launch, compare
with the Firestore usage tab in the Firebase console.

## Owner checklist

- [ ] **Blaze plan and a budget alert** (deploy step 1).
- [ ] **Copy slots.** Fill every `[owner copy: …]` in the app (`OwnerCopy`), the widget names and
  descriptions, and the privacy page's release date.
- [ ] **App Group and widget in the Apple developer portal.** Register the App Group
  `group.com.nart.wuserade`, add it to the app's identifier, and register the widget extension's
  bundle ID (`com.nart.wuserade.widgets`) with the same App Group. Regenerate the
  provisioning profiles.
- [ ] **Lock-screen widget on a real device.** Add each widget (medium, small, lock screen), check
  they show today's poem, and tap through to the reader. Receive one real morning poem at a chosen
  time and tap it.
- [ ] **App Store privacy labels.** Add Product Interaction (linked to the user, app functionality).
  Decide on Device ID too: the app now stores the push token and a random install ID under the
  reader's account. `PrivacyInfo.xcprivacy` declares it as linked, for app functionality.
- [ ] **Delete one test user.** An earlier test run created one anonymous user in the production
  project. Delete it in the Firebase console under Authentication > Users.
