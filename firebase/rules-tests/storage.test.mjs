// Cloud Storage security rules tests. Run through the emulator, never against production:
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
import { deleteObject, getBytes, listAll, ref, updateMetadata, uploadBytes } from 'firebase/storage'

const rulesPath = fileURLToPath(new URL('../storage.rules', import.meta.url))

let testEnv

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-wuserade',
    storage: { rules: readFileSync(rulesPath, 'utf8') },
  })
})

after(async () => {
  await testEnv?.cleanup()
})

beforeEach(async () => {
  await testEnv.clearStorage()
})

const reader = (uid, claims = {}) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'apple.com' }, ...claims }).storage()
const googleReader = (uid) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'google.com' } }).storage()
const anonymousReader = (uid) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).storage()
// A token minted right after linking can still say `anonymous`; its identities name the linked provider.
const linkedReader = (uid, identities, claims = {}) =>
  testEnv.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous', identities }, ...claims }).storage()
const anon = () => testEnv.unauthenticatedContext().storage()

const MAX_BYTES = 5 * 1024 * 1024
const WAITING = 'photo-submissions/7/alice.jpg'
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9])
const asJpeg = { contentType: 'image/jpeg' }

const upload = (storage, path, bytes = jpeg, metadata = asJpeg) =>
  uploadBytes(ref(storage, path), bytes, metadata)

// Puts a file in place the way the admin tool would, without going through the rules.
const seed = (path) =>
  testEnv.withSecurityRulesDisabled(async (ctx) => {
    await upload(ctx.storage(), path)
  })

test('a signed-in reader can upload and overwrite their own photo', async () => {
  for (const storage of [reader('alice'), googleReader('alice')]) {
    await assertSucceeds(upload(storage, WAITING))
    await assertSucceeds(upload(storage, WAITING))
  }
})

test('anonymous, signed-out and banned readers cannot upload', async () => {
  for (const storage of [anonymousReader('alice'), anon(), reader('alice', { photoBan: true })]) {
    await assertFails(upload(storage, WAITING))
  }
})

test('an account with a linked Apple or Google identity can upload, whatever its token says', async () => {
  for (const identities of [{ 'apple.com': ['001'] }, { 'google.com': ['002'] }, { email: ['a@b.c'], 'google.com': ['002'] }]) {
    const storage = linkedReader('alice', identities)
    await assertSucceeds(upload(storage, WAITING))
    await assertSucceeds(upload(storage, WAITING))
  }
})

test('an anonymous token with no Apple or Google identity cannot upload', async () => {
  for (const identities of [{}, { email: ['a@b.c'] }, { 'facebook.com': ['003'] }]) {
    await assertFails(upload(linkedReader('alice', identities), WAITING))
  }
})

test('a banned reader cannot upload, linked identity or not', async () => {
  await assertFails(upload(linkedReader('alice', { 'google.com': ['002'] }, { photoBan: true }), WAITING))
})

test("uploads go only to the reader's own file, as JPEG, up to 5 MB", async () => {
  const storage = reader('alice')
  await assertFails(upload(storage, 'photo-submissions/7/bob.jpg'))
  await assertFails(upload(storage, 'photo-submissions/7/alice.png'))
  await assertFails(upload(storage, WAITING, jpeg, { contentType: 'image/png' }))
  await assertFails(upload(storage, WAITING, new Uint8Array(MAX_BYTES + 1)))
  await assertSucceeds(upload(storage, WAITING, new Uint8Array(MAX_BYTES)))
  await assertFails(upload(storage, 'photo-submissions/x/alice.jpg'))
})

// The poet ID matches the Firestore record rule: a whole number from 1 to 999999, no leading zero.
test('the poet ID is 1 to 999999', async () => {
  const storage = reader('alice')
  await assertSucceeds(upload(storage, 'photo-submissions/1/alice.jpg'))
  await assertSucceeds(upload(storage, 'photo-submissions/999999/alice.jpg'))
  await assertFails(upload(storage, 'photo-submissions/0/alice.jpg'))
  await assertFails(upload(storage, 'photo-submissions/07/alice.jpg'))
  await assertFails(upload(storage, 'photo-submissions/1000000/alice.jpg'))
})

// Overwriting is an update. Changing the file's type through its metadata is an update too.
test("a sender can update their own photo's metadata, but not make it another type", async () => {
  await seed(WAITING)
  const file = ref(reader('alice'), WAITING)
  await assertSucceeds(updateMetadata(file, { customMetadata: { a: 'b' } }))
  await assertFails(updateMetadata(file, { contentType: 'text/html' }))
})

test('only the sender can read and delete a waiting photo', async () => {
  await seed(WAITING)
  const bytes = await assertSucceeds(getBytes(ref(reader('alice'), WAITING)))
  assert.deepEqual(new Uint8Array(bytes), jpeg)
  await assertFails(getBytes(ref(reader('bob'), WAITING)))
  await assertFails(getBytes(ref(anon(), WAITING)))
  await assertFails(deleteObject(ref(reader('bob'), WAITING)))
  await assertFails(deleteObject(ref(anon(), WAITING)))

  await assertSucceeds(deleteObject(ref(reader('alice'), WAITING)))
  // A banned reader can still take their own photo back.
  await seed(WAITING)
  await assertSucceeds(deleteObject(ref(reader('alice', { photoBan: true }), WAITING)))
})

test('nobody can list waiting or approved photos', async () => {
  await seed(WAITING)
  await seed('poets/7.jpg')
  await assertFails(listAll(ref(reader('alice'), 'photo-submissions/7')))
  await assertFails(listAll(ref(anon(), 'poets')))
})

test('approved photos are public and no client can write them', async () => {
  await seed('poets/7.jpg')
  await assertSucceeds(getBytes(ref(anon(), 'poets/7.jpg')))
  await assertFails(upload(reader('alice'), 'poets/7.jpg'))
  await assertFails(deleteObject(ref(reader('alice'), 'poets/7.jpg')))
})

test('everything else is denied', async () => {
  await seed('other/x.jpg')
  const storage = reader('alice')
  await assertFails(upload(storage, 'other/x.jpg'))
  await assertFails(getBytes(ref(storage, 'other/x.jpg')))
})
