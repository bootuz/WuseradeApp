import XCTest
@testable import Wuserade

@MainActor
final class LikesControllerTests: XCTestCase {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)

    // MARK: Fixtures

    private func poem(_ id: Int) -> Poem {
        Poem(id: id, title: "Poem \(id)", author: Author(id: 10 + id, name: "Author \(id)"), content: "Text \(id)")
    }

    private func like(_ id: Int, at date: Date) -> Like {
        Like(poem: poem(id), likedAt: date)
    }

    /// Lets snapshots that are already on their way reach the controller. A snapshot that arrives
    /// after a toggle's change, but was sent before it, shows the older state until the next one.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(20))
    }

    /// A controller bound to `uid`, after the store's first snapshot (here: no likes) has been applied.
    private func makeBoundController(
        store: FakeLikesStore,
        uid: String = "a"
    ) async throws -> LikesController {
        let controller = LikesController(store: store)
        controller.bind(uid: uid)
        try await settle()
        return controller
    }

    // MARK: toggle

    func testToggleAddsThenRemoves() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        XCTAssertFalse(controller.isLiked(1))

        await controller.toggle(poem(1))
        try await settle()
        XCTAssertTrue(controller.isLiked(1))
        XCTAssertEqual(store.likes(for: "a").map(\.poemId), [1])
        XCTAssertEqual(store.likes(for: "a").first?.poem, poem(1), "the like carries a snapshot of the poem")

        await controller.toggle(poem(1))
        try await settle()
        XCTAssertFalse(controller.isLiked(1))
        XCTAssertEqual(store.likes(for: "a"), [])
        XCTAssertEqual(store.calls.filter { $0 == "setLike" || $0 == "removeLike" }, ["setLike", "removeLike"])
    }

    func testToggleFailureReverts() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        store.setSetLikeOutcomes([.failure()])

        await controller.toggle(poem(1))

        XCTAssertFalse(controller.isLiked(1))
        XCTAssertEqual(controller.likes, [])
        XCTAssertEqual(store.likes(for: "a"), [])
    }

    func testUnlikeFailureRestoresTheOriginalLike() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1), like(2, at: t2)], uid: "a")
        let controller = try await makeBoundController(store: store)
        try await waitUntil { controller.likes.count == 2 }
        store.setRemoveLikeOutcomes([.failure()])

        await controller.toggle(poem(1))

        XCTAssertTrue(controller.isLiked(1))
        XCTAssertEqual(controller.likes, [like(2, at: t2), like(1, at: t1)], "back in place, with its original date")
    }

    func testToggleIsOptimisticWhileTheWriteIsPending() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        // Offline, a Firestore write answers only after the device reconnects.
        store.setSetLikeOutcomes([.success(after: .milliseconds(300))])

        let toggle = Task { await controller.toggle(poem(1)) }
        try await waitUntil { store.calls.contains("setLike") }

        XCTAssertTrue(controller.isLiked(1), "shown as liked before the write is confirmed")
        XCTAssertEqual(store.likes(for: "a"), [], "the write has not landed yet")
        await toggle.value
        XCTAssertTrue(controller.isLiked(1))
        XCTAssertEqual(store.likes(for: "a").map(\.poemId), [1])
    }

    func testStaleFailureDoesNotRevertNewerToggle() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        // The first like fails only after the person has already tapped twice more.
        store.setSetLikeOutcomes([.failure(after: .milliseconds(300)), .success()])

        let first = Task { await controller.toggle(poem(1)) }
        try await waitUntil { store.calls.contains("setLike") }
        await controller.toggle(poem(1))   // unlike
        await controller.toggle(poem(1))   // like again
        try await settle()
        XCTAssertTrue(controller.isLiked(1))

        await first.value   // the first write fails now
        try await settle()

        XCTAssertTrue(controller.isLiked(1), "a stale failure must not undo the later tap")
        XCTAssertEqual(store.likes(for: "a").map(\.poemId), [1])
    }

    func testToggleWithoutUidDoesNothing() async throws {
        let store = FakeLikesStore()
        let controller = LikesController(store: store)   // never bound: no account yet

        await controller.toggle(poem(1))

        XCTAssertFalse(controller.isLiked(1))
        XCTAssertEqual(controller.likes, [])
        XCTAssertNil(controller.uid)
        XCTAssertEqual(store.calls, [], "no write, and nothing observed")
    }

    // MARK: bind

    func testBindShowsAndFollowsTheStore() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)

        controller.bind(uid: "a")
        XCTAssertEqual(controller.uid, "a")
        try await waitUntil { controller.likes == [self.like(1, at: self.t1)] }

        // A like added elsewhere (another device) shows up.
        store.seed([like(2, at: t2)], uid: "a")
        try await waitUntil { controller.likes.count == 2 }
        XCTAssertEqual(controller.likes, [like(2, at: t2), like(1, at: t1)])
    }

    func testRebindClearsOldLikes() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)
        controller.bind(uid: "a")
        try await waitUntil { controller.likes == [self.like(1, at: self.t1)] }

        controller.bind(uid: "b")   // "b" has no likes

        XCTAssertEqual(controller.uid, "b")
        XCTAssertEqual(controller.likes, [], "the previous account's likes are gone at once")
        try await waitUntil { store.cancelledObservations == ["a"] }

        // The old account's listener is gone: nothing it emits can reach the list.
        store.seed([like(3, at: t2)], uid: "a")
        store.seed([like(4, at: t2)], uid: "b")
        try await waitUntil { controller.likes.map(\.poemId) == [4] }
        XCTAssertFalse(controller.isLiked(1))
        XCTAssertFalse(controller.isLiked(3))
    }

    func testBindNilClearsLikesAndStopsObserving() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)
        controller.bind(uid: "a")
        try await waitUntil { !controller.likes.isEmpty }

        controller.bind(uid: nil)   // signed out

        XCTAssertNil(controller.uid)
        XCTAssertEqual(controller.likes, [])
        try await waitUntil { store.cancelledObservations == ["a"] }
        await controller.toggle(poem(2))
        XCTAssertFalse(controller.isLiked(2), "liking is off while signed out")
        XCTAssertFalse(store.calls.contains("setLike"))
    }

    func testBindingTheSameUidAgainKeepsTheListener() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)
        controller.bind(uid: "a")
        try await waitUntil { !controller.likes.isEmpty }

        controller.bind(uid: "a")

        XCTAssertEqual(controller.likes, [like(1, at: t1)], "no flash of an empty list")
        XCTAssertEqual(store.calls.filter { $0 == "observeLikes" }.count, 1)
        XCTAssertEqual(store.cancelledObservations, [])
    }

    func testFailureOfTheOldAccountDoesNotChangeTheNewAccountsLikes() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "b")
        let controller = try await makeBoundController(store: store, uid: "a")
        store.setSetLikeOutcomes([.failure(after: .milliseconds(200))])

        let toggle = Task { await controller.toggle(poem(1)) }   // account "a" likes poem 1; the write will fail
        try await waitUntil { store.calls.contains("setLike") }
        controller.bind(uid: "b")                                // the person switches to "b", who has liked poem 1
        try await waitUntil { controller.isLiked(1) }
        await toggle.value

        XCTAssertTrue(controller.isLiked(1), "undoing a's failed like must not remove b's like")
        XCTAssertEqual(controller.likes, [like(1, at: t1)])
    }
}
