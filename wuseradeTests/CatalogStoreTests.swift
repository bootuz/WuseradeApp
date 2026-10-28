import XCTest
@testable import Wuserade

/// In-memory `ContentRepository` for tests. Never touches Firestore or the network.
final class FakeContentRepository: ContentRepository, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private var _meta: ContentMeta
    private var _chunks: [Int: CatalogChunk]
    private var _isOffline = false
    private var _metaCalls = 0
    private var _chunkCalls = 0
    /// Chunk indices that answer late, so tests can prove results are kept in index order
    /// even when chunks finish out of order.
    private var _slowChunks: Set<Int> = []

    init(meta: ContentMeta, chunks: [CatalogChunk]) {
        _meta = meta
        _chunks = Dictionary(uniqueKeysWithValues: chunks.enumerated().map { ($0.offset, $0.element) })
    }

    var metaCalls: Int { lock.withLock { _metaCalls } }
    var chunkCalls: Int { lock.withLock { _chunkCalls } }

    func set(meta: ContentMeta, chunks: [CatalogChunk]) {
        lock.withLock {
            _meta = meta
            _chunks = Dictionary(uniqueKeysWithValues: chunks.enumerated().map { ($0.offset, $0.element) })
        }
    }

    func setOffline(_ offline: Bool) {
        lock.withLock { _isOffline = offline }
    }

    func setSlowChunks(_ indices: Set<Int>) {
        lock.withLock { _slowChunks = indices }
    }

    func resetCounts() {
        lock.withLock {
            _metaCalls = 0
            _chunkCalls = 0
        }
    }

    func fetchMeta() async throws -> ContentMeta {
        try lock.withLock {
            _metaCalls += 1
            if _isOffline { throw Offline() }
            return _meta
        }
    }

    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk {
        let (isSlow, chunk): (Bool, CatalogChunk) = try lock.withLock {
            _chunkCalls += 1
            if _isOffline { throw Offline() }
            guard let chunk = _chunks[index] else { throw Offline() }
            return (_slowChunks.contains(index), chunk)
        }
        if isSlow { try await Task.sleep(nanoseconds: 50_000_000) }
        return chunk
    }

    func fetchPoem(id: Int) async throws -> Poem {
        throw Offline()
    }
}

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
            nextPoemId: 100,
            minimumAppVersion: nil
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
}
