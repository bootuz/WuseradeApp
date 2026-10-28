import Foundation
import Observation
import os

enum CatalogStoreError: LocalizedError, Equatable {
    /// A chunk was published at a different catalog version than `meta/content` announced,
    /// which happens while the admin tool is mid-publish.
    case chunkVersionMismatch(index: Int, expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case let .chunkVersionMismatch(index, expected, found):
            return "Catalog chunk \(index) is at version \(found), expected \(expected)."
        }
    }
}

/// Holds the poem catalog, authors and themes. Starts from the on-disk cache so the UI has data
/// immediately, then `refresh()` brings it up to date. A failed refresh never discards what is already loaded.
@MainActor
@Observable
final class CatalogStore {
    let repository: ContentRepository
    @ObservationIgnored private let cache: CatalogCache

    private(set) var catalog: Catalog?
    private(set) var meta: ContentMeta?
    /// True only while `refresh()` is running.
    private(set) var isLoading = false
    /// The most recent refresh failure; cleared when a refresh succeeds.
    private(set) var lastError: Error?

    var authors: [Author] { meta?.authors.map(\.author) ?? [] }
    var themes: [Category] { meta?.themes ?? [] }

    init(repository: ContentRepository, cache: CatalogCache) {
        self.repository = repository
        self.cache = cache
        if let cached = cache.load() {
            catalog = cached.catalog
            meta = cached.meta
        }
    }

    /// Fetches `meta/content` and, only when its `catalogVersion` differs from the loaded catalog's,
    /// every catalog chunk. New content is accepted only as a consistent whole and is then saved to the cache.
    /// Any failure leaves the current `catalog` and `meta` untouched and is reported through `lastError`.
    /// A call made while a refresh is already running returns immediately.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let newMeta = try await repository.fetchMeta()
            let newCatalog: Catalog
            if let catalog, catalog.version == newMeta.catalogVersion {
                newCatalog = catalog
            } else {
                newCatalog = try await fetchCatalog(for: newMeta)
            }
            apply(meta: newMeta, catalog: newCatalog)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private func apply(meta newMeta: ContentMeta, catalog newCatalog: Catalog) {
        guard newMeta != meta || newCatalog != catalog else { return }
        meta = newMeta
        catalog = newCatalog
        do {
            try cache.save(CachedContent(meta: newMeta, catalog: newCatalog))
        } catch {
            // The content is already loaded; failing to persist it only costs a cold start next launch.
            Self.logger.error("Could not save catalog cache: \(error.localizedDescription)")
        }
    }

    /// Reads every chunk concurrently and joins them in index order.
    /// Throws if any read fails or any chunk is not at `meta.catalogVersion`.
    private func fetchCatalog(for meta: ContentMeta) async throws -> Catalog {
        let repository = repository
        let fetched = try await withThrowingTaskGroup(of: (index: Int, chunk: CatalogChunk).self) { group in
            for index in 0..<meta.catalogChunks {
                group.addTask {
                    (index, try await repository.fetchCatalogChunk(index: index))
                }
            }
            var chunks: [(index: Int, chunk: CatalogChunk)] = []
            for try await result in group {
                chunks.append(result)
            }
            return chunks
        }

        let ordered = fetched.sorted { $0.index < $1.index }
        for (index, chunk) in ordered where chunk.version != meta.catalogVersion {
            throw CatalogStoreError.chunkVersionMismatch(
                index: index,
                expected: meta.catalogVersion,
                found: chunk.version
            )
        }
        return Catalog(version: meta.catalogVersion, entries: ordered.flatMap(\.chunk.entries))
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "CatalogStore"
    )
}
