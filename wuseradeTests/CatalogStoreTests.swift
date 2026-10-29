import Foundation
import Testing
@testable import Wuserade

@MainActor
final class CatalogStoreTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own empty cache directory.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CatalogStoreTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
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

    @Test func `Fresh store loads and caches catalog`() async {
        let fake = makeFake()
        // The first chunk answers last; entries must still come out in chunk order.
        fake.setSlowChunks([0])
        let store = makeStore(fake)
        #expect(store.catalog == nil)

        await store.refresh()

        #expect(store.catalog?.version == 3)
        #expect(store.catalog?.entries.count == 5)
        #expect(store.catalog?.entries.map(\.id) == [1, 2, 3, 4, 5])
        #expect(store.meta?.catalogVersion == 3)
        #expect(store.lastError == nil)
        #expect(!store.isLoading)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("catalog-cache.json").path
        ))
    }

    @Test func `Second store reads cache without network`() async {
        let first = makeStore(makeFake())
        await first.refresh()
        #expect(first.catalog?.version == 3)

        let offline = makeFake()
        offline.setOffline(true)
        let second = makeStore(offline)
        // Loaded synchronously in init, before any refresh.
        #expect(second.catalog?.version == 3)
        #expect(second.catalog?.entries.count == 5)
        #expect(second.meta?.catalogVersion == 3)
        #expect(second.catalog == first.catalog)

        await second.refresh()

        #expect(second.catalog?.version == 3)
        #expect(second.catalog?.entries.count == 5)
        #expect(second.lastError != nil)
        #expect(!second.isLoading)
    }

    @Test func `Same version does not refetch chunks`() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        #expect(fake.chunkCalls == 2)

        fake.resetCounts()
        await store.refresh()

        #expect(fake.metaCalls == 1)
        #expect(fake.chunkCalls == 0)
        #expect(store.catalog?.version == 3)
        #expect(store.lastError == nil)
    }

    @Test func `New version refetches`() async {
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

        #expect(fake.chunkCalls == 2)
        #expect(store.catalog?.version == 4)
        #expect(store.catalog?.entries.map(\.id) == [1, 2, 3, 4, 5, 6])
        #expect(store.meta?.catalogVersion == 4)
        #expect(store.lastError == nil)

        // The new catalog was persisted, not just kept in memory.
        let reopened = makeStore(makeFake())
        #expect(reopened.catalog?.version == 4)
        #expect(reopened.catalog?.entries.count == 6)
    }

    @Test func `Chunk version mismatch keeps old catalog`() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog
        #expect(before?.version == 3)

        // Mid-publish: meta already says v4 and chunk 0 is v4, but chunk 1 is still v3.
        fake.set(
            meta: meta(version: 4, chunks: 2),
            chunks: [
                CatalogChunk(version: 4, entries: [summary(1), summary(2), summary(7)]),
                CatalogChunk(version: 3, entries: [summary(4), summary(5)]),
            ]
        )
        await store.refresh()

        #expect(store.catalog?.version == 3)
        #expect(store.catalog == before)
        #expect(store.meta?.catalogVersion == 3)
        #expect(store.lastError != nil)
        #expect(!store.isLoading)

        // The rejected catalog was not written to the cache either.
        let reopened = makeStore(makeFake())
        #expect(reopened.catalog == before)

        // Once the publish finishes, the next refresh picks the new catalog up and clears the error.
        fake.set(
            meta: meta(version: 4, chunks: 2),
            chunks: [
                CatalogChunk(version: 4, entries: [summary(1), summary(2), summary(7)]),
                CatalogChunk(version: 4, entries: [summary(4), summary(5)]),
            ]
        )
        await store.refresh()
        #expect(store.catalog?.version == 4)
        #expect(store.lastError == nil)
    }

    @Test func `Offline first launch ends loading with error`() async {
        let fake = makeFake()
        fake.setOffline(true)
        let store = makeStore(fake)

        await store.refresh()

        #expect(!store.isLoading)
        #expect(store.catalog == nil)
        #expect(store.meta == nil)
        #expect(store.lastError != nil)
        #expect(store.authors.isEmpty)
        #expect(store.themes.isEmpty)
    }

    @Test func `Authors and themes come from meta`() async {
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
        #expect(store.authors.isEmpty)
        #expect(store.themes.isEmpty)

        await store.refresh()

        #expect(store.authors == [Author(id: 4, name: "Лашэ"), Author(id: 7, name: "Бемырзэ")])
        #expect(store.themes == [Category(id: 9, title: "Хы"), Category(id: 2, title: "Гущlэ")])
    }

    // MARK: Malformed catalogChunks

    /// A hand-edited `catalogChunks` below 1 is refused like any other failed refresh:
    /// the loaded and cached catalog stay, and the minimum app version still gets through.
    @Test(arguments: [0, -1])
    func `Malformed catalog chunks keep loaded catalog`(count: Int) async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog
        #expect(before?.version == 3)

        fake.set(meta: meta(version: 4, chunks: count), chunks: [])
        fake.set(minimumAppVersion: "9.0")
        fake.resetCounts()
        await store.refresh()

        #expect(store.lastError as? CatalogStoreError == .invalidChunkCount(count))
        #expect(fake.chunkCalls == 0)
        #expect(store.catalog == before)
        #expect(store.meta?.catalogVersion == 3)
        #expect(!store.isLoading)
        #expect(store.minimumAppVersion == "9.0")
        // Neither the bad meta nor an empty catalog reached the cache.
        let reopened = makeStore(makeFake())
        #expect(reopened.catalog == before)
        #expect(reopened.meta?.catalogVersion == 3)
    }

    // MARK: Minimum app version

    /// One `rebuild --min-version` that also changes the chunk shape: this build cannot read the new chunks,
    /// but must still learn that it has to be updated.
    @Test func `Minimum app version applied when chunks fail`() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog
        #expect(store.minimumAppVersion == nil)

        // No chunk at version 4 can be read.
        fake.set(meta: meta(version: 4, chunks: 2), chunks: [])
        fake.set(minimumAppVersion: "9.0")
        await store.refresh()

        #expect(store.minimumAppVersion == "9.0")
        #expect(!AppVersion.isSupported(current: "1.0", minimum: store.minimumAppVersion))
        #expect(store.lastError != nil)
        #expect(store.catalog == before)
        #expect(store.meta?.catalogVersion == 3)
    }

    /// A new shape for `meta/content` itself must not hide the minimum either.
    @Test func `Minimum app version applied when rest of meta does not decode`() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        let before = store.catalog

        fake.setMetaUndecodable(true)
        fake.set(minimumAppVersion: "9.0")
        fake.resetCounts()
        await store.refresh()

        #expect(store.minimumAppVersion == "9.0")
        #expect(store.lastError != nil)
        #expect(fake.chunkCalls == 0)
        #expect(store.catalog == before)
        #expect(store.meta?.catalogVersion == 3)
    }

    @Test func `Cleared minimum app version lifts gate`() async {
        let fake = makeFake()
        fake.set(minimumAppVersion: "9.0")
        let store = makeStore(fake)
        await store.refresh()
        #expect(store.minimumAppVersion == "9.0")

        fake.set(minimumAppVersion: nil)
        await store.refresh()

        #expect(store.minimumAppVersion == nil)
        #expect(AppVersion.isSupported(current: "1.0", minimum: store.minimumAppVersion))
        // Cleared on disk too, so the next launch does not bring the gate back.
        let offline = makeFake()
        offline.setOffline(true)
        #expect(makeStore(offline).minimumAppVersion == nil)
    }

    @Test func `Minimum app version survives relaunch without network`() async {
        let fake = makeFake()
        let store = makeStore(fake)
        await store.refresh()
        fake.set(meta: meta(version: 4, chunks: 2), chunks: [])
        fake.set(minimumAppVersion: "9.0")
        await store.refresh()
        #expect(store.minimumAppVersion == "9.0")

        let offline = makeFake()
        offline.setOffline(true)
        let relaunched = makeStore(offline)
        // Loaded synchronously in init, before any refresh.
        #expect(relaunched.minimumAppVersion == "9.0")
        #expect(!AppVersion.isSupported(current: "1.0", minimum: relaunched.minimumAppVersion))

        await relaunched.refresh()

        #expect(relaunched.lastError != nil)
        #expect(relaunched.minimumAppVersion == "9.0")
        #expect(relaunched.catalog?.version == 3)
    }
}
