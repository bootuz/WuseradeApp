import Foundation
import Testing
@testable import Wuserade

@MainActor
struct PhotoSubmissionsTests {
    private let jpeg = Data([0xFF, 0xD8, 0xFF])

    // MARK: Fixtures

    private struct PoetIDsFailure: Error {}

    /// Bound to `uid` (alice unless told otherwise); `poetIDs` answers `[7, 8, 9]` unless told otherwise.
    private func makeSubmissions(
        store: FakePhotoSubmissionStore,
        uid: String? = "alice",
        poetIDs: @escaping @MainActor () async throws -> [Int] = { [7, 8, 9] }
    ) -> PhotoSubmissions {
        let submissions = PhotoSubmissions(store: store, poetIDs: poetIDs)
        submissions.bind(uid: uid)
        return submissions
    }

    // MARK: uid(for:)

    @Test func `Uid for state`() {
        #expect(PhotoSubmissions.uid(for: .signedOut) == nil)
        #expect(PhotoSubmissions.uid(for: .anonymous(uid: "a")) == nil, "an anonymous account cannot send")
        #expect(PhotoSubmissions.uid(for: .signedIn(uid: "a", provider: .apple, email: nil)) == "a")
    }

    // MARK: check

    @Test func `Check reads the record`() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        #expect(submissions.status(poetID: 7) == .unchecked)

        await submissions.check(poetID: 7)
        await submissions.check(poetID: 8)

        #expect(submissions.status(poetID: 7) == .waiting)
        #expect(submissions.status(poetID: 8) == .notWaiting)
        #expect(store.calls == ["isWaiting 7_alice", "isWaiting 8_alice"])
    }

    @Test func `Check failure is failed`() async {
        let store = FakePhotoSubmissionStore()
        store.isWaitingError = FakePhotoSubmissionStore.Failure()
        let submissions = makeSubmissions(store: store)

        await submissions.check(poetID: 7)

        #expect(submissions.status(poetID: 7) == .failed)
    }

    @Test func `Check without uid does nothing`() async {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store, uid: nil)

        await submissions.check(poetID: 7)

        #expect(store.calls == [])
        #expect(submissions.status(poetID: 7) == .unchecked)
    }

    @Test func `Check that finishes after another uid is bound is dropped`() async throws {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        store.isWaitingDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let aliceCheck = Task { await submissions.check(poetID: 7) }
        try await waitUntil { store.calls == ["isWaiting 7_alice"] }
        submissions.bind(uid: "bob")
        await aliceCheck.value

        #expect(submissions.status(poetID: 7) == .unchecked, "alice's answer says nothing about bob")
    }

    @Test func `Check that finishes after a successful send does not overwrite it`() async throws {
        let store = FakePhotoSubmissionStore()
        store.isWaitingDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        // The check reads the record before the send writes it, then answers late.
        let check = Task { await submissions.check(poetID: 7) }
        try await waitUntil { store.calls == ["isWaiting 7_alice"] }
        try await submissions.send(jpeg, for: 7)
        #expect(submissions.status(poetID: 7) == .waiting)
        await check.value

        #expect(submissions.status(poetID: 7) == .waiting, "the late answer predates the send")
        #expect(store.calls == ["isWaiting 7_alice", "send 7_alice"])
    }

    @Test func `Check that finishes after a failed send still applies`() async throws {
        let store = FakePhotoSubmissionStore()
        store.isWaitingDelay = .milliseconds(200)
        store.sendError = FakePhotoSubmissionStore.Failure()
        let submissions = makeSubmissions(store: store)

        let check = Task { await submissions.check(poetID: 7) }
        try await waitUntil { store.calls == ["isWaiting 7_alice"] }
        try? await submissions.send(jpeg, for: 7)
        await check.value

        #expect(submissions.status(poetID: 7) == .notWaiting, "a send that failed changed nothing")
    }

    // MARK: send

    @Test func `Send marks the record waiting`() async throws {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store)

        try await submissions.send(jpeg, for: 7)

        #expect(submissions.status(poetID: 7) == .waiting)
        #expect(!submissions.isSending(poetID: 7))
        #expect(store.calls == ["send 7_alice"])
    }

    @Test func `Failed send keeps status and rethrows`() async {
        let store = FakePhotoSubmissionStore()
        store.sendError = PhotoSubmissionError.banned
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)
        #expect(submissions.status(poetID: 7) == .notWaiting)

        await #expect(throws: PhotoSubmissionError.banned, "expected the send to throw") {
            try await submissions.send(jpeg, for: 7)
        }

        #expect(submissions.status(poetID: 7) == .notWaiting)
        #expect(!submissions.isSending(poetID: 7))
    }

    @Test func `Send without uid throws not signed in`() async {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store, uid: nil)

        await #expect(throws: PhotoSubmissionError.notSignedIn, "expected the send to throw") {
            try await submissions.send(jpeg, for: 7)
        }

        #expect(store.calls == [])
    }

    @Test func `Second send while sending is ignored`() async throws {
        let store = FakePhotoSubmissionStore()
        store.sendDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let first = Task { try await submissions.send(jpeg, for: 7) }
        try await waitUntil { submissions.isSending(poetID: 7) }

        try await submissions.send(jpeg, for: 7)
        try await first.value

        #expect(store.calls == ["send 7_alice"])
        #expect(submissions.status(poetID: 7) == .waiting)
        #expect(!submissions.isSending(poetID: 7))
    }

    @Test func `Send for another poet is not blocked by sending one`() async throws {
        let store = FakePhotoSubmissionStore()
        store.sendDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let poet7 = Task { try await submissions.send(jpeg, for: 7) }
        try await waitUntil { submissions.isSending(poetID: 7) }
        let poet8 = Task { try await submissions.send(jpeg, for: 8) }
        try await waitUntil { submissions.isSending(poetID: 8) }
        #expect(submissions.isSending(poetID: 7), "poet 7's send is still in flight")
        try await poet7.value
        try await poet8.value

        #expect(store.calls == ["send 7_alice", "send 8_alice"], "both reached the store")
        #expect(submissions.status(poetID: 7) == .waiting)
        #expect(submissions.status(poetID: 8) == .waiting)
    }

    @Test func `Send that finishes after another uid is bound does not mark the new uid`() async throws {
        let store = FakePhotoSubmissionStore()
        store.sendDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let aliceSend = Task { try await submissions.send(jpeg, for: 7) }
        try await waitUntil { submissions.isSending(poetID: 7) }
        submissions.bind(uid: "bob")
        #expect(!submissions.isSending(poetID: 7), "bob has no send in flight")
        try await aliceSend.value

        #expect(store.waiting == ["7_alice"])
        #expect(submissions.status(poetID: 7) == .unchecked, "alice's send says nothing about bob")
        #expect(!submissions.isSending(poetID: 7))
    }

    // MARK: bind

    @Test func `Bind to another uid forgets statuses`() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)
        #expect(submissions.status(poetID: 7) == .waiting)

        submissions.bind(uid: "bob")

        #expect(submissions.uid == "bob")
        #expect(submissions.status(poetID: 7) == .unchecked)
        await submissions.check(poetID: 7)
        #expect(store.calls.last == "isWaiting 7_bob")
        #expect(submissions.status(poetID: 7) == .notWaiting)
    }

    @Test func `Bind to the same uid keeps statuses`() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)

        submissions.bind(uid: "alice")

        #expect(submissions.status(poetID: 7) == .waiting)
    }

    @Test func `Bind to nil forgets statuses`() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)

        submissions.bind(uid: nil)

        #expect(submissions.uid == nil)
        #expect(submissions.status(poetID: 7) == .unchecked)
    }

    // MARK: deleteAll

    @Test func `Delete all deletes every poet's record`() async throws {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice", "9_alice", "7_bob"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)
        #expect(submissions.status(poetID: 7) == .waiting)
        let readCalls = store.calls

        try await submissions.deleteAll(uid: "alice")

        let deleteCalls = store.calls.dropFirst(readCalls.count)
        #expect(Set(deleteCalls) == ["delete 7_alice", "delete 8_alice", "delete 9_alice"])
        #expect(deleteCalls.count == 3)
        #expect(store.waiting == ["7_bob"], "only alice's records go")
        #expect(submissions.status(poetID: 7) == .unchecked, "the statuses are forgotten")
    }

    @Test func `Delete all rethrows when poet IDs fail`() async {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store, poetIDs: { throw PoetIDsFailure() })

        await #expect(throws: PoetIDsFailure.self, "expected deleteAll to throw") {
            try await submissions.deleteAll(uid: "alice")
        }

        #expect(store.calls == [])
    }

    @Test func `Delete all rethrows when a delete fails`() async {
        let store = FakePhotoSubmissionStore()
        store.deleteError = FakePhotoSubmissionStore.Failure()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)

        await #expect(throws: FakePhotoSubmissionStore.Failure.self, "expected deleteAll to throw") {
            try await submissions.deleteAll(uid: "alice")
        }

        #expect(submissions.status(poetID: 7) == .waiting, "a failed delete forgets nothing")
    }
}
