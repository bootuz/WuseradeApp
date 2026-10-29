import Foundation
import Testing
@testable import Wuserade

@MainActor
final class ReadsControllerTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own defaults suite.
    private let suiteName = "ReadsControllerTests-\(UUID().uuidString)"

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func `Each poem is written once per account`() async throws {
        let store = FakeReadsStore()
        let controller = ReadsController(store: store, defaults: try defaults())

        // No account: nothing is written.
        controller.markRead(7)
        await settle()
        #expect(store.calls == [])

        controller.bind(uid: "alice")
        controller.markRead(7)
        controller.markRead(7)
        await settle()
        controller.markRead(7)
        await settle()
        #expect(store.calls == ["markRead 7 alice"])

        // Another account writes its own read.
        controller.bind(uid: "bob")
        controller.markRead(7)
        await settle()
        #expect(store.calls == ["markRead 7 alice", "markRead 7 bob"])

        // The written reads are remembered on the device, across launches.
        let relaunched = ReadsController(store: store, defaults: try defaults())
        relaunched.bind(uid: "alice")
        relaunched.markRead(7)
        relaunched.markRead(8)
        await settle()
        #expect(store.calls == ["markRead 7 alice", "markRead 7 bob", "markRead 8 alice"])
        #expect(store.reads(for: "alice") == [7, 8])
    }

    @Test func `Nothing is written while paused`() async throws {
        let store = FakeReadsStore()
        var paused = true
        let controller = ReadsController(store: store, defaults: try defaults(), isPaused: { paused })
        controller.bind(uid: "alice")

        controller.markRead(7)
        await settle()
        #expect(store.calls == [], "no read is written while an account operation runs")

        paused = false
        controller.markRead(7)
        await settle()
        #expect(store.calls == ["markRead 7 alice"])
    }

    @Test func `A failed write is dropped and tried again next time`() async throws {
        let store = FakeReadsStore()
        let controller = ReadsController(store: store, defaults: try defaults())
        controller.bind(uid: "alice")
        store.setMarkReadError(FakeReadsStore.Failure())

        controller.markRead(7)
        await settle()
        #expect(store.reads(for: "alice") == [])

        store.setMarkReadError(nil)
        controller.markRead(7)
        await settle()
        #expect(store.calls == ["markRead 7 alice", "markRead 7 alice"])
        #expect(store.reads(for: "alice") == [7])
    }
}
