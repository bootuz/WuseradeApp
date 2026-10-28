import Foundation

/// What is persisted between launches: the last accepted meta and the catalog assembled at its version.
struct CachedContent: Codable {
    let meta: ContentMeta
    let catalog: Catalog
}

/// Stores the last accepted `CachedContent` as one JSON file so the UI has data
/// on launch before (or without) any network.
struct CatalogCache {
    static let fileName = "catalog-cache.json"

    /// The app's cache, in Application Support (created on first use).
    static var `default`: CatalogCache {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return CatalogCache(directory: directory)
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    /// The cached content, or nil when there is no cache file or it cannot be decoded.
    func load() -> CachedContent? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedContent.self, from: data)
    }

    /// Writes atomically, so a crash mid-write never leaves a truncated cache behind.
    func save(_ content: CachedContent) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Default date coding stores the exact `TimeInterval`, so entries compare equal after a round trip.
        let data = try JSONEncoder().encode(content)
        try data.write(to: fileURL, options: .atomic)
    }
}
