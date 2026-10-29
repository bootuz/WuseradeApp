import Foundation
import SwiftData
import Testing
@testable import Wuserade

@MainActor
final class LegacyLikesMigratorTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own defaults suite.
    private let suiteName = "LegacyLikesMigratorTests-\(UUID().uuidString)"

    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_002_000)

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: Fixtures

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func didMigrate() throws -> Bool {
        try makeDefaults().bool(forKey: "didMigrateLocalLikes")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PersistedPoem.self, PersistedAuthor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func persist(_ id: Int, at date: Date, in container: ModelContainer) throws {
        container.mainContext.insert(
            PersistedPoem(
                poemID: id,
                title: "Poem \(id)",
                author: PersistedAuthor(authorID: 10 + id, name: "Author \(id)"),
                text: "Text \(id)",
                persistedDate: date
            )
        )
        try container.mainContext.save()
    }

    private func legacyLike(_ id: Int, at date: Date) -> Like {
        Like(
            poemId: id,
            likedAt: date,
            title: "Poem \(id)",
            authorId: 10 + id,
            authorName: "Author \(id)",
            text: "Text \(id)"
        )
    }

    private func makeMigrator(_ container: ModelContainer, _ store: FakeLikesStore) throws -> LegacyLikesMigrator {
        LegacyLikesMigrator(container: container, store: store, defaults: try makeDefaults())
    }

    // MARK: Tests

    @Test func `Uploads persisted poems with persisted date`() async throws {
        let container = try makeContainer()
        try persist(1, at: t1, in: container)
        try persist(2, at: t3, in: container)
        let store = FakeLikesStore()
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")

        #expect(store.likes(for: "a") == [legacyLike(2, at: t3), legacyLike(1, at: t1)])
        #expect(store.calls == ["setLikes"], "one batched write")
        #expect(try didMigrate())
    }

    @Test func `Sets flag and does not run twice`() async throws {
        let container = try makeContainer()
        try persist(1, at: t1, in: container)
        let store = FakeLikesStore()
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")
        #expect(try didMigrate())

        // A poem that appears later, or another account on the same device, is not uploaded.
        try persist(2, at: t2, in: container)
        await migrator.migrateIfNeeded(uid: "a")
        await migrator.migrateIfNeeded(uid: "b")

        #expect(store.calls == ["setLikes"])
        #expect(store.likes(for: "a") == [legacyLike(1, at: t1)])
        #expect(store.likes(for: "b") == [])
    }

    @Test func `Failure leaves flag unset`() async throws {
        let container = try makeContainer()
        try persist(1, at: t1, in: container)
        let store = FakeLikesStore()
        store.setSetLikesError(FakeLikesStore.Failure())
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")

        #expect(try !didMigrate())
        #expect(store.likes(for: "a") == [])

        // The next try, once the write works, uploads and sets the flag.
        store.setSetLikesError(nil)
        await migrator.migrateIfNeeded(uid: "a")

        #expect(try didMigrate())
        #expect(store.likes(for: "a") == [legacyLike(1, at: t1)])
    }

    @Test func `Nothing to upload still sets the flag`() async throws {
        let store = FakeLikesStore()
        let migrator = try makeMigrator(makeContainer(), store)

        await migrator.migrateIfNeeded(uid: "a")

        #expect(store.calls == [], "nothing to write")
        #expect(try didMigrate())
    }

    @Test func `Duplicate poems keep the earliest date`() async throws {
        let container = try makeContainer()
        try persist(1, at: t2, in: container)
        try persist(1, at: t1, in: container)
        let store = FakeLikesStore()
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")

        #expect(store.likes(for: "a") == [legacyLike(1, at: t1)])
    }
}
