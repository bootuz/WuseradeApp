import Foundation
import Testing
@testable import Wuserade

@MainActor
final class LibraryPhotoTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own empty cache directory.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibraryPhotoTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    /// One chunk with one poem, so a refresh accepts the meta.
    private func makeFake(authors: [AuthorEntry]) -> FakeContentRepository {
        FakeContentRepository(
            meta: ContentMeta(
                catalogVersion: 1,
                catalogChunks: 1,
                authors: authors,
                themes: [],
                nextPoemId: 100
            ),
            chunks: [
                CatalogChunk(version: 1, entries: [
                    PoemSummary(
                        id: 1,
                        title: "Poem 1",
                        authorId: 7,
                        authorName: "Author 7",
                        themeId: nil,
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ]),
            ]
        )
    }

    private func makeStore(_ fake: FakeContentRepository) -> CatalogStore {
        CatalogStore(repository: fake, cache: CatalogCache(directory: directory))
    }

    // MARK: Tests

    @Test func `Photo URL of poet`() async {
        let fake = makeFake(authors: [
            AuthorEntry(id: 7, name: "Author 7", poemsCount: 3, photoURL: "https://x/7.jpg"),
            AuthorEntry(id: 8, name: "Author 8", poemsCount: 1),
            AuthorEntry(id: 9, name: "Author 9", poemsCount: 2, photoURL: "authors/9.jpg"),
        ])
        let store = makeStore(fake)
        let library = Library(store: store)
        await store.refresh()

        #expect(library.photoURL(ofPoet: 7) == URL(string: "https://x/7.jpg"))
        #expect(library.photoURL(ofPoet: 8) == nil)
        #expect(library.photoURL(ofPoet: 9) == nil)
        #expect(library.photoURL(ofPoet: 42) == nil)
    }

    @Test func `Poet IDs loads meta when missing`() async throws {
        let fake = makeFake(authors: [
            AuthorEntry(id: 7, name: "Author 7", poemsCount: 3),
            AuthorEntry(id: 8, name: "Author 8", poemsCount: 1),
        ])
        let library = Library(store: makeStore(fake))

        let ids = try await library.poetIDs()

        #expect(ids == [7, 8])
        #expect(fake.metaCalls == 1)
    }

    @Test func `Poet IDs throws when meta cannot load`() async {
        let fake = makeFake(authors: [AuthorEntry(id: 7, name: "Author 7", poemsCount: 3)])
        fake.setOffline(true)
        let library = Library(store: makeStore(fake))

        await #expect(throws: FakeContentRepository.Offline.self, "poetIDs() should throw when meta cannot load") {
            _ = try await library.poetIDs()
        }
    }
}
