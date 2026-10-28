import Foundation
import Observation
import os

enum CatalogStoreError: LocalizedError, Equatable {
    /// A chunk was published at a different catalog version than `meta/content` announced,
    /// which happens while the admin tool is mid-publish.
    case chunkVersionMismatch(index: Int, expected: Int, found: Int)
    /// `meta/content.catalogChunks` is below 1, which only a bad hand edit in the console produces.
    case invalidChunkCount(Int)

    var errorDescription: String? {
        switch self {
        case let .chunkVersionMismatch(index, expected, found):
            return "Catalog chunk \(index) is at version \(found), expected \(expected)."
        case let .invalidChunkCount(count):
            return "meta/content.catalogChunks is \(count), expected at least 1."
        }
    }
}

/// Holds the poem catalog, authors and themes, and the minimum app version. Starts from the on-disk cache
/// so the UI has data immediately, then `refresh()` brings it up to date. A failed refresh never discards
/// what is already loaded.
@MainActor
@Observable
final class CatalogStore {
    let repository: ContentRepository
    @ObservationIgnored private let cache: CatalogCache

    private(set) var catalog: Catalog?
    private(set) var meta: ContentMeta?
    /// `meta/content.minimumAppVersion` from the latest read of `meta/content`, kept across launches.
    /// Nil until `meta/content` has been read once, and after the minimum is cleared.
    private(set) var minimumAppVersion: String?
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
        minimumAppVersion = cache.loadMinimumAppVersion()
    }

    /// Fetches `meta/content` and, only when its `catalogVersion` differs from the loaded catalog's,
    /// every catalog chunk. New content is accepted only as a consistent whole and is then saved to the cache.
    /// Any failure leaves the current `catalog` and `meta` untouched and is reported through `lastError`.
    /// `minimumAppVersion` is the exception: it is applied and saved as soon as `meta/content` is read.
    /// A call made while a refresh is already running returns immediately.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let document = try await repository.fetchMeta()
            // First, before anything else can fail: a build too old to decode the rest of `meta/content`
            // or the new chunks must still learn that it has to be updated.
            applyMinimumAppVersion(document.minimumAppVersion)
            let newMeta = try document.meta.get()
            // A negative count would trap below; 0 would replace the catalog with an empty one.
            guard newMeta.catalogChunks >= 1 else {
                throw CatalogStoreError.invalidChunkCount(newMeta.catalogChunks)
            }
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

    private func applyMinimumAppVersion(_ version: String?) {
        guard version != minimumAppVersion else { return }
        minimumAppVersion = version
        // Saved on its own, so the gate holds on the next launch even if no catalog at this version ever loads.
        do {
            try cache.saveMinimumAppVersion(version)
        } catch {
            Self.logger.error("Could not save the minimum app version: \(error.localizedDescription)")
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
