import SwiftData
import XCTest
@testable import Wuserade

@MainActor
final class LegacyLikesMigratorTests: XCTestCase {
    /// XCTest creates one instance per test method, so every test gets its own defaults suite.
    private let suiteName = "LegacyLikesMigratorTests-\(UUID().uuidString)"

    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_002_000)

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: Fixtures

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

    func testUploadsPersistedPoemsWithPersistedDate() async throws {
        let container = try makeContainer()
        try persist(1, at: t1, in: container)
        try persist(2, at: t3, in: container)
        let store = FakeLikesStore()
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")

        XCTAssertEqual(store.likes(for: "a"), [legacyLike(2, at: t3), legacyLike(1, at: t1)])
        XCTAssertEqual(store.calls, ["setLikes"], "one batched write")
        XCTAssertTrue(try didMigrate())
    }

    func testSetsFlagAndDoesNotRunTwice() async throws {
        let container = try makeContainer()
        try persist(1, at: t1, in: container)
        let store = FakeLikesStore()
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")
        XCTAssertTrue(try didMigrate())

        // A poem that appears later, or another account on the same device, is not uploaded.
        try persist(2, at: t2, in: container)
        await migrator.migrateIfNeeded(uid: "a")
        await migrator.migrateIfNeeded(uid: "b")

        XCTAssertEqual(store.calls, ["setLikes"])
        XCTAssertEqual(store.likes(for: "a"), [legacyLike(1, at: t1)])
        XCTAssertEqual(store.likes(for: "b"), [])
    }

    func testFailureLeavesFlagUnset() async throws {
        let container = try makeContainer()
        try persist(1, at: t1, in: container)
        let store = FakeLikesStore()
        store.setSetLikesError(FakeLikesStore.Failure())
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")

        XCTAssertFalse(try didMigrate())
        XCTAssertEqual(store.likes(for: "a"), [])

        // The next try, once the write works, uploads and sets the flag.
        store.setSetLikesError(nil)
        await migrator.migrateIfNeeded(uid: "a")

        XCTAssertTrue(try didMigrate())
        XCTAssertEqual(store.likes(for: "a"), [legacyLike(1, at: t1)])
    }

    func testNothingToUploadStillSetsTheFlag() async throws {
        let store = FakeLikesStore()
        let migrator = try makeMigrator(makeContainer(), store)

        await migrator.migrateIfNeeded(uid: "a")

        XCTAssertEqual(store.calls, [], "nothing to write")
        XCTAssertTrue(try didMigrate())
    }

    func testDuplicatePoemsKeepTheEarliestDate() async throws {
        let container = try makeContainer()
        try persist(1, at: t2, in: container)
        try persist(1, at: t1, in: container)
        let store = FakeLikesStore()
        let migrator = try makeMigrator(container, store)

        await migrator.migrateIfNeeded(uid: "a")

        XCTAssertEqual(store.likes(for: "a"), [legacyLike(1, at: t1)])
    }
}
