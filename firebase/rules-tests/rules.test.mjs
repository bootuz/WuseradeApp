// Firestore security rules tests. Run through the emulator, never against production:
//   npx -y firebase-tools@latest emulators:exec --project demo-wuserade --only firestore "npm --prefix rules-tests test"
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
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  Timestamp,
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
  await testEnv.cleanup()
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
