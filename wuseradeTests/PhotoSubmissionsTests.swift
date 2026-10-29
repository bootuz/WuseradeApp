import XCTest
@testable import Wuserade

@MainActor
final class PhotoSubmissionsTests: XCTestCase {
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

    func testUidForState() {
        XCTAssertNil(PhotoSubmissions.uid(for: .signedOut))
        XCTAssertNil(PhotoSubmissions.uid(for: .anonymous(uid: "a")), "an anonymous account cannot send")
        XCTAssertEqual(PhotoSubmissions.uid(for: .signedIn(uid: "a", provider: .apple, email: nil)), "a")
    }

    // MARK: check

    func testCheckReadsTheRecord() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        XCTAssertEqual(submissions.status(poetID: 7), .unchecked)

        await submissions.check(poetID: 7)
        await submissions.check(poetID: 8)

        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
        XCTAssertEqual(submissions.status(poetID: 8), .notWaiting)
        XCTAssertEqual(store.calls, ["isWaiting 7_alice", "isWaiting 8_alice"])
    }

    func testCheckFailureIsFailed() async {
        let store = FakePhotoSubmissionStore()
        store.isWaitingError = FakePhotoSubmissionStore.Failure()
        let submissions = makeSubmissions(store: store)

        await submissions.check(poetID: 7)

        XCTAssertEqual(submissions.status(poetID: 7), .failed)
    }

    func testCheckWithoutUidDoesNothing() async {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store, uid: nil)

        await submissions.check(poetID: 7)

        XCTAssertEqual(store.calls, [])
        XCTAssertEqual(submissions.status(poetID: 7), .unchecked)
    }

    func testCheckThatFinishesAfterAnotherUidIsBoundIsDropped() async throws {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        store.isWaitingDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let aliceCheck = Task { await submissions.check(poetID: 7) }
        try await waitUntil { store.calls == ["isWaiting 7_alice"] }
        submissions.bind(uid: "bob")
        await aliceCheck.value

        XCTAssertEqual(submissions.status(poetID: 7), .unchecked, "alice's answer says nothing about bob")
    }

    func testCheckThatFinishesAfterASuccessfulSendDoesNotOverwriteIt() async throws {
        let store = FakePhotoSubmissionStore()
        store.isWaitingDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        // The check reads the record before the send writes it, then answers late.
        let check = Task { await submissions.check(poetID: 7) }
        try await waitUntil { store.calls == ["isWaiting 7_alice"] }
        try await submissions.send(jpeg, for: 7)
        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
        await check.value

        XCTAssertEqual(submissions.status(poetID: 7), .waiting, "the late answer predates the send")
        XCTAssertEqual(store.calls, ["isWaiting 7_alice", "send 7_alice"])
    }

    func testCheckThatFinishesAfterAFailedSendStillApplies() async throws {
        let store = FakePhotoSubmissionStore()
        store.isWaitingDelay = .milliseconds(200)
        store.sendError = FakePhotoSubmissionStore.Failure()
        let submissions = makeSubmissions(store: store)

        let check = Task { await submissions.check(poetID: 7) }
        try await waitUntil { store.calls == ["isWaiting 7_alice"] }
        try? await submissions.send(jpeg, for: 7)
        await check.value

        XCTAssertEqual(submissions.status(poetID: 7), .notWaiting, "a send that failed changed nothing")
    }

    // MARK: send

    func testSendMarksTheRecordWaiting() async throws {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store)

        try await submissions.send(jpeg, for: 7)

        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
        XCTAssertFalse(submissions.isSending(poetID: 7))
        XCTAssertEqual(store.calls, ["send 7_alice"])
    }

    func testFailedSendKeepsStatusAndRethrows() async {
        let store = FakePhotoSubmissionStore()
        store.sendError = PhotoSubmissionError.banned
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)
        XCTAssertEqual(submissions.status(poetID: 7), .notWaiting)

        do {
            try await submissions.send(jpeg, for: 7)
            XCTFail("expected the send to throw")
        } catch {
            XCTAssertEqual(error as? PhotoSubmissionError, .banned)
        }

        XCTAssertEqual(submissions.status(poetID: 7), .notWaiting)
        XCTAssertFalse(submissions.isSending(poetID: 7))
    }

    func testSendWithoutUidThrowsNotSignedIn() async {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store, uid: nil)

        do {
            try await submissions.send(jpeg, for: 7)
            XCTFail("expected the send to throw")
        } catch {
            XCTAssertEqual(error as? PhotoSubmissionError, .notSignedIn)
        }

        XCTAssertEqual(store.calls, [])
    }

    func testSecondSendWhileSendingIsIgnored() async throws {
        let store = FakePhotoSubmissionStore()
        store.sendDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let first = Task { try await submissions.send(jpeg, for: 7) }
        try await waitUntil { submissions.isSending(poetID: 7) }

        try await submissions.send(jpeg, for: 7)
        try await first.value

        XCTAssertEqual(store.calls, ["send 7_alice"])
        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
        XCTAssertFalse(submissions.isSending(poetID: 7))
    }

    func testSendForAnotherPoetIsNotBlockedBySendingOne() async throws {
        let store = FakePhotoSubmissionStore()
        store.sendDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let poet7 = Task { try await submissions.send(jpeg, for: 7) }
        try await waitUntil { submissions.isSending(poetID: 7) }
        let poet8 = Task { try await submissions.send(jpeg, for: 8) }
        try await waitUntil { submissions.isSending(poetID: 8) }
        XCTAssertTrue(submissions.isSending(poetID: 7), "poet 7's send is still in flight")
        try await poet7.value
        try await poet8.value

        XCTAssertEqual(store.calls, ["send 7_alice", "send 8_alice"], "both reached the store")
        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
        XCTAssertEqual(submissions.status(poetID: 8), .waiting)
    }

    func testSendThatFinishesAfterAnotherUidIsBoundDoesNotMarkTheNewUid() async throws {
        let store = FakePhotoSubmissionStore()
        store.sendDelay = .milliseconds(200)
        let submissions = makeSubmissions(store: store)

        let aliceSend = Task { try await submissions.send(jpeg, for: 7) }
        try await waitUntil { submissions.isSending(poetID: 7) }
        submissions.bind(uid: "bob")
        XCTAssertFalse(submissions.isSending(poetID: 7), "bob has no send in flight")
        try await aliceSend.value

        XCTAssertEqual(store.waiting, ["7_alice"])
        XCTAssertEqual(submissions.status(poetID: 7), .unchecked, "alice's send says nothing about bob")
        XCTAssertFalse(submissions.isSending(poetID: 7))
    }

    // MARK: bind

    func testBindToAnotherUidForgetsStatuses() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)
        XCTAssertEqual(submissions.status(poetID: 7), .waiting)

        submissions.bind(uid: "bob")

        XCTAssertEqual(submissions.uid, "bob")
        XCTAssertEqual(submissions.status(poetID: 7), .unchecked)
        await submissions.check(poetID: 7)
        XCTAssertEqual(store.calls.last, "isWaiting 7_bob")
        XCTAssertEqual(submissions.status(poetID: 7), .notWaiting)
    }

    func testBindToTheSameUidKeepsStatuses() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)

        submissions.bind(uid: "alice")

        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
    }

    func testBindToNilForgetsStatuses() async {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)

        submissions.bind(uid: nil)

        XCTAssertNil(submissions.uid)
        XCTAssertEqual(submissions.status(poetID: 7), .unchecked)
    }

    // MARK: deleteAll

    func testDeleteAllDeletesEveryPoetsRecord() async throws {
        let store = FakePhotoSubmissionStore()
        store.waiting = ["7_alice", "9_alice", "7_bob"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)
        XCTAssertEqual(submissions.status(poetID: 7), .waiting)
        let readCalls = store.calls

        try await submissions.deleteAll(uid: "alice")

        let deleteCalls = store.calls.dropFirst(readCalls.count)
        XCTAssertEqual(Set(deleteCalls), ["delete 7_alice", "delete 8_alice", "delete 9_alice"])
        XCTAssertEqual(deleteCalls.count, 3)
        XCTAssertEqual(store.waiting, ["7_bob"], "only alice's records go")
        XCTAssertEqual(submissions.status(poetID: 7), .unchecked, "the statuses are forgotten")
    }

    func testDeleteAllRethrowsWhenPoetIDsFail() async {
        let store = FakePhotoSubmissionStore()
        let submissions = makeSubmissions(store: store, poetIDs: { throw PoetIDsFailure() })

        do {
            try await submissions.deleteAll(uid: "alice")
            XCTFail("expected deleteAll to throw")
        } catch {
            XCTAssertTrue(error is PoetIDsFailure)
        }

        XCTAssertEqual(store.calls, [])
    }

    func testDeleteAllRethrowsWhenADeleteFails() async {
        let store = FakePhotoSubmissionStore()
        store.deleteError = FakePhotoSubmissionStore.Failure()
        store.waiting = ["7_alice"]
        let submissions = makeSubmissions(store: store)
        await submissions.check(poetID: 7)

        do {
            try await submissions.deleteAll(uid: "alice")
            XCTFail("expected deleteAll to throw")
        } catch {
            XCTAssertTrue(error is FakePhotoSubmissionStore.Failure)
        }

        XCTAssertEqual(submissions.status(poetID: 7), .waiting, "a failed delete forgets nothing")
    }
}
