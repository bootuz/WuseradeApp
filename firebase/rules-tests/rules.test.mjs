// Firestore security rules tests. Run through the emulator, never against production:
//   npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore,storage "npm --prefix rules-tests test"
import { test, before, after, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing'
import {
  collection,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  Timestamp,
  where,
} from 'firebase/firestore'

// Denied writes are expected here; keep the SDK from logging each one.
setLogLevel('silent')

const rulesPath = fileURLToPath(new URL('../firestore.rules', import.meta.url))

let testEnv

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-wuserade',
    firestore: { rules: readFileSync(rulesPath, 'utf8') },
  })
})

after(async () => {
  await testEnv?.cleanup()
})

beforeEach(async () => {
  await testEnv.clearFirestore()
})

const alice = () => testEnv.authenticatedContext('alice').firestore()
const anon = () => testEnv.unauthenticatedContext().firestore()

const validLike = (overrides = {}) => ({
  poemId: 5,
  likedAt: Timestamp.now(),
  title: 'т',
  authorId: 1,
  authorName: 'а',
  text: 'x',
  ...overrides,
})

const withoutKey = (obj, key) => {
  const { [key]: _omitted, ...rest } = obj
  return rest
}

test('anyone can read content', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    await setDoc(doc(db, 'poems/1'), { id: 1 })
    await setDoc(doc(db, 'authors/1'), { id: 1 })
    await setDoc(doc(db, 'themes/1'), { id: 1 })
    await setDoc(doc(db, 'catalog/0'), { version: 1 })
    await setDoc(doc(db, 'meta/content'), { catalogVersion: 1 })
  })
  const db = anon()
  for (const path of ['poems/1', 'authors/1', 'themes/1', 'catalog/0', 'meta/content']) {
    await assertSucceeds(getDoc(doc(db, path)))
  }
})

// The app only ever gets content documents by ID. One unauthenticated query on poems
// would bill ~4,000 reads, so listing a content collection is denied.
test('nobody can list or query content', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    await setDoc(doc(db, 'poems/1'), { id: 1 })
    await setDoc(doc(db, 'catalog/0'), { version: 1 })
  })
  for (const db of [anon(), alice()]) {
    for (const path of ['poems', 'authors', 'themes', 'catalog', 'meta']) {
      await assertFails(getDocs(collection(db, path)))
    }
    await assertFails(getDocs(query(collection(db, 'poems'), orderBy('id'))))
    // Getting one document by its ID still works.
    await assertSucceeds(getDoc(doc(db, 'poems/1')))
    await assertSucceeds(getDoc(doc(db, 'catalog/0')))
  }
})

test('nobody can write content', async () => {
  const db = alice()
  for (const path of ['poems/1', 'catalog/0', 'meta/content']) {
    await assertFails(setDoc(doc(db, path), { id: 1 }))
  }
})

test('owner can write a valid like', async () => {
  await assertSucceeds(setDoc(doc(alice(), 'users/alice/likes/5'), validLike()))
})

test('like poemId must match doc id', async () => {
  await assertFails(setDoc(doc(alice(), 'users/alice/likes/5'), validLike({ poemId: 6 })))
})

test('like must have exact fields', async () => {
  const db = alice()
  const ref = doc(db, 'users/alice/likes/5')
  await assertFails(setDoc(ref, withoutKey(validLike(), 'text')))
  await assertFails(setDoc(ref, validLike({ foo: 'bar' })))
  await assertFails(setDoc(ref, validLike({ authorId: '1' })))
})

test('cannot touch another user', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    await setDoc(doc(db, 'users/bob'), { createdAt: Timestamp.now() })
    await setDoc(doc(db, 'users/bob/likes/5'), validLike())
  })
  const db = alice()
  await assertFails(getDoc(doc(db, 'users/bob/likes/5')))
  await assertFails(setDoc(doc(db, 'users/bob/likes/5'), validLike()))
  await assertFails(deleteDoc(doc(db, 'users/bob/likes/5')))
  await assertFails(getDoc(doc(db, 'users/bob')))
  await assertFails(setDoc(doc(db, 'users/bob'), { createdAt: Timestamp.now() }))
  await assertFails(deleteDoc(doc(db, 'users/bob')))
  // signed-out clients get no access to user data either
  await assertFails(getDoc(doc(anon(), 'users/bob/likes/5')))
  await assertFails(getDoc(doc(anon(), 'users/bob')))
})

test('owner can create, read, delete own user doc and likes', async () => {
  const db = alice()
  const userRef = doc(db, 'users/alice')
  const likeRef = doc(db, 'users/alice/likes/5')

  await assertSucceeds(setDoc(userRef, { createdAt: Timestamp.now() }))
  await assertSucceeds(setDoc(userRef, { createdAt: Timestamp.now(), displayName: 'Alice' }))
  await assertSucceeds(getDoc(userRef))

  await assertSucceeds(setDoc(likeRef, validLike()))
  await assertSucceeds(getDoc(likeRef))

  await assertSucceeds(deleteDoc(likeRef))
  await assertSucceeds(deleteDoc(userRef))
})

// What `ensureUserDocument` writes on first launch.
test('owner can create own user doc with a server timestamp', async () => {
  await assertSucceeds(setDoc(doc(alice(), 'users/alice'), { createdAt: serverTimestamp() }))
  await assertFails(setDoc(doc(alice(), 'users/bob'), { createdAt: serverTimestamp() }))
})

// The likes listener and `fetchLikes` query by `likedAt`; `deleteAllData` lists the collection.
test('owner can query own likes', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    await setDoc(doc(db, 'users/alice/likes/5'), validLike())
    await setDoc(doc(db, 'users/alice/likes/6'), validLike({ poemId: 6 }))
  })
  const likes = collection(alice(), 'users/alice/likes')
  const ordered = await assertSucceeds(getDocs(query(likes, orderBy('likedAt', 'desc'))))
  assert.equal(ordered.size, 2)
  const all = await assertSucceeds(getDocs(likes))
  assert.equal(all.size, 2)
})

test("cannot query another user's likes", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/bob/likes/5'), validLike())
  })
  for (const db of [alice(), anon()]) {
    const likes = collection(db, 'users/bob/likes')
    await assertFails(getDocs(query(likes, orderBy('likedAt', 'desc'))))
    await assertFails(getDocs(likes))
  }
})

test('user doc must have exact fields', async () => {
  const db = alice()
  const ref = doc(db, 'users/alice')
  await assertFails(setDoc(ref, {}))
  await assertFails(setDoc(ref, { createdAt: 'now' }))
  await assertFails(setDoc(ref, { createdAt: Timestamp.now(), displayName: 7 }))
  await assertFails(setDoc(ref, { createdAt: Timestamp.now(), foo: 'bar' }))
})

test('unknown collections are denied', async () => {
  const db = alice()
  await assertFails(getDoc(doc(db, 'other/1')))
  await assertFails(setDoc(doc(db, 'other/1'), { id: 1 }))
})

// Photo records: signed in with Apple or Google, a ban claim blocks sending, and the ID,
// shape and server time are all checked. Reads and deletes look at the ID only.
const reader = (uid, claims = {}) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'apple.com' }, ...claims }).firestore()
const googleReader = (uid) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'google.com' } }).firestore()
const anonymousReader = (uid) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).firestore()
// A token minted right after linking can still say `anonymous`; its identities name the linked provider.
const linkedReader = (uid, identities, claims = {}) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous', identities }, ...claims }).firestore()
const submission = (overrides = {}) =>
  ({ authorId: 7, submittedBy: 'alice', createdAt: serverTimestamp(), ...overrides })

test('a signed-in reader can send and resend a photo record', async () => {
  for (const db of [reader('alice'), googleReader('alice')]) {
    const ref = doc(db, 'photoSubmissions/7_alice')
    await assertSucceeds(setDoc(ref, submission()))
    await assertSucceeds(setDoc(ref, submission()))
  }
})

test('anonymous, signed-out and banned readers cannot send a record', async () => {
  for (const db of [anonymousReader('alice'), anon(), reader('alice', { photoBan: true })]) {
    await assertFails(setDoc(doc(db, 'photoSubmissions/7_alice'), submission()))
  }
})

test('an account with a linked Apple or Google identity can send a record, whatever its token says', async () => {
  for (const identities of [{ 'apple.com': ['001'] }, { 'google.com': ['002'] }, { email: ['a@b.c'], 'google.com': ['002'] }]) {
    const ref = doc(linkedReader('alice', identities), 'photoSubmissions/7_alice')
    await assertSucceeds(setDoc(ref, submission()))
    await assertSucceeds(setDoc(ref, submission()))
  }
})

test('an anonymous token with no Apple or Google identity cannot send a record', async () => {
  for (const identities of [{}, { email: ['a@b.c'] }, { 'facebook.com': ['003'] }]) {
    await assertFails(setDoc(doc(linkedReader('alice', identities), 'photoSubmissions/7_alice'), submission()))
  }
})

test('a banned reader cannot send a record, linked identity or not', async () => {
  const db = linkedReader('alice', { 'google.com': ['002'] }, { photoBan: true })
  await assertFails(setDoc(doc(db, 'photoSubmissions/7_alice'), submission()))
})

test('a record must match its ID and shape', async () => {
  const db = reader('alice')
  const ref = doc(db, 'photoSubmissions/7_alice')
  await assertFails(setDoc(doc(db, 'photoSubmissions/7_bob'), submission()))
  await assertFails(setDoc(ref, submission({ authorId: 8 })))
  await assertFails(setDoc(ref, submission({ submittedBy: 'bob' })))
  await assertFails(setDoc(ref, submission({ createdAt: Timestamp.now() })))
  await assertFails(setDoc(ref, submission({ foo: 'bar' })))
  for (const key of ['authorId', 'submittedBy', 'createdAt']) {
    await assertFails(setDoc(ref, withoutKey(submission(), key)))
  }
  await assertFails(setDoc(ref, submission({ authorId: '7' })))
})

// The poet ID matches the Storage path rule: a whole number from 1 to 999999.
test('the poet ID is 1 to 999999', async () => {
  const db = reader('alice')
  for (const authorId of [1, 999999]) {
    await assertSucceeds(setDoc(doc(db, `photoSubmissions/${authorId}_alice`), submission({ authorId })))
  }
  for (const authorId of [0, -7, 1000000]) {
    await assertFails(setDoc(doc(db, `photoSubmissions/${authorId}_alice`), submission({ authorId })))
  }
})

test("a reader can get and delete only their own record, even when it doesn't exist", async () => {
  const ref = (db) => doc(db, 'photoSubmissions/7_alice')
  const snapshot = await assertSucceeds(getDoc(ref(reader('alice'))))
  assert.equal(snapshot.exists(), false)
  await assertSucceeds(deleteDoc(ref(reader('alice'))))
  await assertFails(getDoc(ref(reader('bob'))))
  await assertFails(deleteDoc(ref(reader('bob'))))
  await assertFails(getDoc(ref(anon())))
  await assertFails(deleteDoc(ref(anon())))
  // The ID must be exactly `{authorId}_{uid}`.
  await assertFails(getDoc(doc(reader('alice'), 'photoSubmissions/7_alice_x')))
  await assertFails(deleteDoc(doc(reader('alice'), 'photoSubmissions/7_alice_x')))
  // A banned reader can still take their own photo back.
  await assertSucceeds(deleteDoc(ref(reader('alice', { photoBan: true }))))
})

test('nobody can list photo records', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), 'photoSubmissions/7_alice'),
      submission({ createdAt: Timestamp.now() }),
    )
  })
  const db = reader('alice')
  const submissions = collection(db, 'photoSubmissions')
  await assertFails(getDocs(submissions))
  await assertFails(getDocs(query(submissions, where('submittedBy', '==', 'alice'))))
  // Even a query pinned to one document ID is a list, and a list is denied.
  await assertFails(getDocs(query(submissions, where(documentId(), '==', '7_alice'))))
})
