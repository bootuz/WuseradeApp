import Foundation
import Testing
@testable import Wuserade

@MainActor
struct LikesControllerTests {
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

    @Test func `Toggle adds then removes`() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        #expect(!controller.isLiked(1))

        await controller.toggle(poem(1))
        try await settle()
        #expect(controller.isLiked(1))
        #expect(store.likes(for: "a").map(\.poemId) == [1])
        #expect(store.likes(for: "a").first?.poem == poem(1), "the like carries a snapshot of the poem")

        await controller.toggle(poem(1))
        try await settle()
        #expect(!controller.isLiked(1))
        #expect(store.likes(for: "a") == [])
        #expect(store.calls.filter { $0 == "setLike" || $0 == "removeLike" } == ["setLike", "removeLike"])
    }

    @Test func `Toggle failure reverts`() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        store.setSetLikeOutcomes([.failure()])

        await controller.toggle(poem(1))

        #expect(!controller.isLiked(1))
        #expect(controller.likes == [])
        #expect(store.likes(for: "a") == [])
    }

    @Test func `Unlike failure restores the original like`() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1), like(2, at: t2)], uid: "a")
        let controller = try await makeBoundController(store: store)
        try await waitUntil { controller.likes.count == 2 }
        store.setRemoveLikeOutcomes([.failure()])

        await controller.toggle(poem(1))

        #expect(controller.isLiked(1))
        #expect(controller.likes == [like(2, at: t2), like(1, at: t1)], "back in place, with its original date")
    }

    @Test func `Toggle is optimistic while the write is pending`() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        // Offline, a Firestore write answers only after the device reconnects.
        store.setSetLikeOutcomes([.success(after: .milliseconds(300))])

        let toggle = Task { await controller.toggle(poem(1)) }
        try await waitUntil { store.calls.contains("setLike") }

        #expect(controller.isLiked(1), "shown as liked before the write is confirmed")
        #expect(store.likes(for: "a") == [], "the write has not landed yet")
        await toggle.value
        #expect(controller.isLiked(1))
        #expect(store.likes(for: "a").map(\.poemId) == [1])
    }

    @Test func `Stale failure does not revert newer toggle`() async throws {
        let store = FakeLikesStore()
        let controller = try await makeBoundController(store: store)
        // The first like fails only after the person has already tapped twice more.
        store.setSetLikeOutcomes([.failure(after: .milliseconds(300)), .success()])

        let first = Task { await controller.toggle(poem(1)) }
        try await waitUntil { store.calls.contains("setLike") }
        await controller.toggle(poem(1))   // unlike
        await controller.toggle(poem(1))   // like again
        try await settle()
        #expect(controller.isLiked(1))

        await first.value   // the first write fails now
        try await settle()

        #expect(controller.isLiked(1), "a stale failure must not undo the later tap")
        #expect(store.likes(for: "a").map(\.poemId) == [1])
    }

    @Test func `Toggle without uid does nothing`() async throws {
        let store = FakeLikesStore()
        let controller = LikesController(store: store)   // never bound: no account yet

        await controller.toggle(poem(1))

        #expect(!controller.isLiked(1))
        #expect(controller.likes == [])
        #expect(controller.uid == nil)
        #expect(store.calls == [], "no write, and nothing observed")
    }

    // MARK: bind

    @Test func `Bind shows and follows the store`() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)

        controller.bind(uid: "a")
        #expect(controller.uid == "a")
        try await waitUntil { controller.likes == [self.like(1, at: self.t1)] }

        // A like added elsewhere (another device) shows up.
        store.seed([like(2, at: t2)], uid: "a")
        try await waitUntil { controller.likes.count == 2 }
        #expect(controller.likes == [like(2, at: t2), like(1, at: t1)])
    }

    @Test func `Rebind clears old likes`() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)
        controller.bind(uid: "a")
        try await waitUntil { controller.likes == [self.like(1, at: self.t1)] }

        controller.bind(uid: "b")   // "b" has no likes

        #expect(controller.uid == "b")
        #expect(controller.likes == [], "the previous account's likes are gone at once")
        try await waitUntil { store.cancelledObservations == ["a"] }

        // The old account's listener is gone: nothing it emits can reach the list.
        store.seed([like(3, at: t2)], uid: "a")
        store.seed([like(4, at: t2)], uid: "b")
        try await waitUntil { controller.likes.map(\.poemId) == [4] }
        #expect(!controller.isLiked(1))
        #expect(!controller.isLiked(3))
    }

    @Test func `Bind nil clears likes and stops observing`() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)
        controller.bind(uid: "a")
        try await waitUntil { !controller.likes.isEmpty }

        controller.bind(uid: nil)   // signed out

        #expect(controller.uid == nil)
        #expect(controller.likes == [])
        try await waitUntil { store.cancelledObservations == ["a"] }
        await controller.toggle(poem(2))
        #expect(!controller.isLiked(2), "liking is off while signed out")
        #expect(!store.calls.contains("setLike"))
    }

    @Test func `Binding the same uid again keeps the listener`() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "a")
        let controller = LikesController(store: store)
        controller.bind(uid: "a")
        try await waitUntil { !controller.likes.isEmpty }

        controller.bind(uid: "a")

        #expect(controller.likes == [like(1, at: t1)], "no flash of an empty list")
        #expect(store.calls.filter { $0 == "observeLikes" }.count == 1)
        #expect(store.cancelledObservations == [])
    }

    @Test func `Failure of the old account does not change the new account's likes`() async throws {
        let store = FakeLikesStore()
        store.seed([like(1, at: t1)], uid: "b")
        let controller = try await makeBoundController(store: store, uid: "a")
        store.setSetLikeOutcomes([.failure(after: .milliseconds(200))])

        let toggle = Task { await controller.toggle(poem(1)) }   // account "a" likes poem 1; the write will fail
        try await waitUntil { store.calls.contains("setLike") }
        controller.bind(uid: "b")                                // the person switches to "b", who has liked poem 1
        try await waitUntil { controller.isLiked(1) }
        await toggle.value

        #expect(controller.isLiked(1), "undoing a's failed like must not remove b's like")
        #expect(controller.likes == [like(1, at: t1)])
    }
}
