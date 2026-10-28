#if DEBUG
import Foundation

/// A few poems, authors and themes for SwiftUI previews.
enum PreviewContent {
    static let authors = [
        AuthorEntry(id: 1, name: "Усакlуэм и цlэр", poemsCount: 2),
        AuthorEntry(id: 2, name: "Тхакlуэм и цlэр", poemsCount: 1),
    ]

    static let themes = [
        Category(id: 1, title: "Лъагъуныгъэ"),
        Category(id: 2, title: "Хэку"),
    ]

    static let catalog = Catalog(version: 1, entries: [
        entry(1, title: "Гъатхэ", authorId: 1, themeId: 1, daysAgo: 3),
        entry(2, title: "Бжьыхьэ", authorId: 1, themeId: 2, daysAgo: 2),
        entry(3, title: "Щlымахуэ", authorId: 2, themeId: 1, daysAgo: 1),
    ])

    static let meta = ContentMeta(
        catalogVersion: catalog.version,
        catalogChunks: 1,
        authors: authors,
        themes: themes,
        nextPoemId: 4,
        minimumAppVersion: nil
    )

    private static func entry(_ id: Int, title: String, authorId: Int, themeId: Int, daysAgo: Double) -> PoemSummary {
        PoemSummary(
            id: id,
            title: title,
            authorId: authorId,
            authorName: authors.first { $0.id == authorId }?.name ?? "",
            themeId: themeId,
            createdAt: Date(timeIntervalSinceNow: -daysAgo * 86_400)
        )
    }
}

/// Serves `PreviewContent` from memory, so a preview never reaches Firestore.
struct PreviewContentRepository: ContentRepository {
    struct Offline: Error {}

    /// When true every read fails, as on a first launch without network.
    var isOffline = false

    func fetchMeta() async throws -> ContentMeta {
        if isOffline { throw Offline() }
        return PreviewContent.meta
    }

    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk {
        if isOffline { throw Offline() }
        return CatalogChunk(version: PreviewContent.catalog.version, entries: PreviewContent.catalog.entries)
    }

    func fetchPoem(id: Int) async throws -> Poem {
        if isOffline { throw Offline() }
        return Poem.example
    }
}

extension CatalogStore {
    /// A store for previews, backed by its own temporary cache. When `loaded`, it starts with
    /// `PreviewContent`; otherwise it starts empty and every refresh fails (the offline first-launch state).
    static func preview(loaded: Bool = true) -> CatalogStore {
        let cache = CatalogCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewCatalog-\(UUID().uuidString)", isDirectory: true))
        if loaded {
            try? cache.save(CachedContent(meta: PreviewContent.meta, catalog: PreviewContent.catalog))
        }
        return CatalogStore(repository: PreviewContentRepository(isOffline: !loaded), cache: cache)
    }
}
#endif
