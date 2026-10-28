import XCTest
@testable import Wuserade

@MainActor
final class CatalogStoreTests: XCTestCase {
    /// XCTest creates one instance per test method, so every test gets its own empty cache directory.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CatalogStoreTests-\(UUID().uuidString)", isDirectory: true)

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    private func summary(_ id: Int, authorId: Int = 1, themeId: Int? = nil) -> PoemSummary {
        PoemSummary(
            id: id,
            title: "Poem \(id)",
            authorId: authorId,
            authorName: "Author \(authorId)",
            themeId: themeId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id) * 86_400 + 0.25)
        )
    }

    private func meta(
        version: Int,
        chunks: Int,
        authors: [AuthorEntry] = [],
        themes: [Wuserade.Category] = []
    ) -> ContentMeta {
        ContentMeta(
            catalogVersion: version,
            catalogChunks: chunks,
            authors: authors,
            themes: themes,
            nextPoemId: 100
        )
    }

    /// Version 3: two chunks, 3 + 2 entries (ids 1...5).
    private func makeFake(version: Int = 3) -> FakeContentRepository {
        FakeContentRepository(
            meta: meta(version: version, chunks: 2),
            chunks: [
                CatalogChunk(version: version, entries: [summary(1), summary(2), summary(3)]),
                CatalogChunk(version: version, entries: [summary(4), summary(5)]),
            ]
        )
    }

    private func makeStore(_ fake: FakeContentRepository) -> CatalogStore {
        CatalogStore(repository: fake, cache: CatalogCache(directory: directory))
    }

    // MARK: Tests

    func testFreshStoreLoadsAndCachesCatalog() async {
        let fake = makeFake()
        // The first chunk answers last; entries must still come out in chunk order.
        fake.setSlowChunks([0])
        let store = makeStore(fake)
        XCTAssertNil(store.catalog)

        await store.refresh()

        XCTAssertEqual(store.catalog?.version, 3)
        XCTAssertEqual(store.catalog?.entries.count, 5)
        XCTAssertEqual(store.catalog?.entries.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(store.meta?.catalogVersion, 3)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("catalog-cache.json").path
        ))
    }

    func testSecondStoreReadsCacheWithoutNetwork() async {
        let first = makeStore(makeFake())
        await first.refresh()
        XCTAssertEqual(first.catalog?.version, 3)

        let offline = makeFake()
        offline.setOffline(true)
        let second = makeStore(offline)
        // Loaded synchronously in init, before any refresh.
        XCTAssertEqual(second.catalog?.version, 3)
        XCTAssertEqual(second.catalog?.entries.count, 5)
        XCTAssertEqual(second.meta?.catalogVersion, 3)
        XCTAssertEqual(second.catalog, first.catalog)

        await second.refresh()

        XCTAssertEqual(second.catalog?.version, 3)
        XCTAssertEqual(second.catalog?.entries.count, 5)
        XCTAssertNotNil(second.lastError)
        XCTAssertFalse(second.isLoading)
    }

    func testSameVersionDoesNotRefetchChunks() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        XCTAssertEqual(fake.chunkCalls, 2)

        fake.resetCounts()
        await store.refresh()

        XCTAssertEqual(fake.metaCalls, 1)
        XCTAssertEqual(fake.chunkCalls, 0)
        XCTAssertEqual(store.catalog?.version, 3)
        XCTAssertNil(store.lastError)
    }

    func testNewVersionRefetches() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()

        fake.set(
            meta: meta(version: 4, chunks: 2),
            chunks: [
                CatalogChunk(version: 4, entries: [summary(1), summary(2)]),
                CatalogChunk(version: 4, entries: [summary(3), summary(4), summary(5), summary(6)]),
            ]
        )
        fake.resetCounts()
        await store.refresh()

        XCTAssertEqual(fake.chunkCalls, 2)
        XCTAssertEqual(store.catalog?.version, 4)
        XCTAssertEqual(store.catalog?.entries.map(\.id), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(store.meta?.catalogVersion, 4)
        XCTAssertNil(store.lastError)

        // The new catalog was persisted, not just kept in memory.
        let reopened = makeStore(makeFake())
        XCTAssertEqual(reopened.catalog?.version, 4)
        XCTAssertEqual(reopened.catalog?.entries.count, 6)
    }

    func testChunkVersionMismatchKeepsOldCatalog() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog
        XCTAssertEqual(before?.version, 3)

        // Mid-publish: meta already says v4 and chunk 0 is v4, but chunk 1 is still v3.
        fake.set(
            meta: meta(version: 4, chunks: 2),
            chunks: [
                CatalogChunk(version: 4, entries: [summary(1), summary(2), summary(7)]),
                CatalogChunk(version: 3, entries: [summary(4), summary(5)]),
            ]
        )
        await store.refresh()

        XCTAssertEqual(store.catalog?.version, 3)
        XCTAssertEqual(store.catalog, before)
        XCTAssertEqual(store.meta?.catalogVersion, 3)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isLoading)

        // The rejected catalog was not written to the cache either.
        let reopened = makeStore(makeFake())
        XCTAssertEqual(reopened.catalog, before)

        // Once the publish finishes, the next refresh picks the new catalog up and clears the error.
        fake.set(
            meta: meta(version: 4, chunks: 2),
            chunks: [
                CatalogChunk(version: 4, entries: [summary(1), summary(2), summary(7)]),
                CatalogChunk(version: 4, entries: [summary(4), summary(5)]),
            ]
        )
        await store.refresh()
        XCTAssertEqual(store.catalog?.version, 4)
        XCTAssertNil(store.lastError)
    }

    func testOfflineFirstLaunchEndsLoadingWithError() async {
        let fake = makeFake()
        fake.setOffline(true)
        let store = makeStore(fake)

        await store.refresh()

        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.catalog)
        XCTAssertNil(store.meta)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.authors.isEmpty)
        XCTAssertTrue(store.themes.isEmpty)
    }

    func testAuthorsAndThemesComeFromMeta() async {
        let fake = FakeContentRepository(
            meta: meta(
                version: 1,
                chunks: 1,
                authors: [
                    AuthorEntry(id: 4, name: "Лашэ", poemsCount: 12),
                    AuthorEntry(id: 7, name: "Бемырзэ", poemsCount: 3),
                ],
                themes: [Category(id: 9, title: "Хы"), Category(id: 2, title: "Гущlэ")]
            ),
            chunks: [CatalogChunk(version: 1, entries: [summary(1, authorId: 4, themeId: 9)])]
        )
        let store = makeStore(fake)
        XCTAssertTrue(store.authors.isEmpty)
        XCTAssertTrue(store.themes.isEmpty)

        await store.refresh()

        XCTAssertEqual(store.authors, [Author(id: 4, name: "Лашэ"), Author(id: 7, name: "Бемырзэ")])
        XCTAssertEqual(store.themes, [Category(id: 9, title: "Хы"), Category(id: 2, title: "Гущlэ")])
    }

    // MARK: Malformed catalogChunks

    func testZeroCatalogChunksKeepsLoadedCatalog() async {
        await assertRejectsChunkCount(0)
    }

    func testNegativeCatalogChunksKeepsLoadedCatalog() async {
        await assertRejectsChunkCount(-1)
    }

    /// A hand-edited `catalogChunks` below 1 is refused like any other failed refresh:
    /// the loaded and cached catalog stay, and the minimum app version still gets through.
    private func assertRejectsChunkCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog
        XCTAssertEqual(before?.version, 3, file: file, line: line)

        fake.set(meta: meta(version: 4, chunks: count), chunks: [])
        fake.set(minimumAppVersion: "9.0")
        fake.resetCounts()
        await store.refresh()

        XCTAssertEqual(store.lastError as? CatalogStoreError, .invalidChunkCount(count), file: file, line: line)
        XCTAssertEqual(fake.chunkCalls, 0, file: file, line: line)
        XCTAssertEqual(store.catalog, before, file: file, line: line)
        XCTAssertEqual(store.meta?.catalogVersion, 3, file: file, line: line)
        XCTAssertFalse(store.isLoading, file: file, line: line)
        XCTAssertEqual(store.minimumAppVersion, "9.0", file: file, line: line)
        // Neither the bad meta nor an empty catalog reached the cache.
        let reopened = makeStore(makeFake())
        XCTAssertEqual(reopened.catalog, before, file: file, line: line)
        XCTAssertEqual(reopened.meta?.catalogVersion, 3, file: file, line: line)
    }

    // MARK: Minimum app version

    /// One `rebuild --min-version` that also changes the chunk shape: this build cannot read the new chunks,
    /// but must still learn that it has to be updated.
    func testMinimumAppVersionAppliedWhenChunksFail() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog
        XCTAssertNil(store.minimumAppVersion)

        // No chunk at version 4 can be read.
        fake.set(meta: meta(version: 4, chunks: 2), chunks: [])
        fake.set(minimumAppVersion: "9.0")
        await store.refresh()

        XCTAssertEqual(store.minimumAppVersion, "9.0")
        XCTAssertFalse(AppVersion.isSupported(current: "1.0", minimum: store.minimumAppVersion))
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.catalog, before)
        XCTAssertEqual(store.meta?.catalogVersion, 3)
    }

    /// A new shape for `meta/content` itself must not hide the minimum either.
    func testMinimumAppVersionAppliedWhenRestOfMetaDoesNotDecode() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog

        fake.setMetaUndecodable(true)
        fake.set(minimumAppVersion: "9.0")
        fake.resetCounts()
        await store.refresh()

        XCTAssertEqual(store.minimumAppVersion, "9.0")
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(fake.chunkCalls, 0)
        XCTAssertEqual(store.catalog, before)
        XCTAssertEqual(store.meta?.catalogVersion, 3)
    }

    func testClearedMinimumAppVersionLiftsGate() async {
        let fake = makeFake()
        fake.set(minimumAppVersion: "9.0")
        let store = makeStore(fake)
        await store.refresh()
        XCTAssertEqual(store.minimumAppVersion, "9.0")

        fake.set(minimumAppVersion: nil)
        await store.refresh()

        XCTAssertNil(store.minimumAppVersion)
        XCTAssertTrue(AppVersion.isSupported(current: "1.0", minimum: store.minimumAppVersion))
        // Cleared on disk too, so the next launch does not bring the gate back.
        let offline = makeFake()
        offline.setOffline(true)
        XCTAssertNil(makeStore(offline).minimumAppVersion)
    }

    func testMinimumAppVersionSurvivesRelaunchWithoutNetwork() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        fake.set(meta: meta(version: 4, chunks: 2), chunks: [])
        fake.set(minimumAppVersion: "9.0")
        await store.refresh()
        XCTAssertEqual(store.minimumAppVersion, "9.0")

        let offline = makeFake()
        offline.setOffline(true)
        let relaunched = makeStore(offline)
        // Loaded synchronously in init, before any refresh.
        XCTAssertEqual(relaunched.minimumAppVersion, "9.0")
        XCTAssertFalse(AppVersion.isSupported(current: "1.0", minimum: relaunched.minimumAppVersion))

        await relaunched.refresh()

        XCTAssertNotNil(relaunched.lastError)
        XCTAssertEqual(relaunched.minimumAppVersion, "9.0")
        XCTAssertEqual(relaunched.catalog?.version, 3)
    }
}
