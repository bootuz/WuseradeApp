import Foundation

/// What is persisted between launches: the last accepted meta and the catalog assembled at its version.
struct CachedContent: Codable {
    let meta: ContentMeta
    let catalog: Catalog
}

/// Stores the last accepted `CachedContent` as one JSON file so the UI has data
/// on launch before (or without) any network. The minimum app version is kept in a file of its own,
/// because it is accepted without a catalog.
struct CatalogCache {
    static let fileName = "catalog-cache.json"
    static let minimumAppVersionFileName = "minimum-app-version.txt"

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

    var minimumAppVersionFileURL: URL {
        directory.appendingPathComponent(Self.minimumAppVersionFileName)
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

    /// The last `meta/content.minimumAppVersion` read, or nil when there was none.
    func loadMinimumAppVersion() -> String? {
        try? String(contentsOf: minimumAppVersionFileURL, encoding: .utf8)
    }

    /// Writes `version` atomically, or removes the file when it is nil (the minimum was cleared).
    func saveMinimumAppVersion(_ version: String?) throws {
        guard let version else {
            if FileManager.default.fileExists(atPath: minimumAppVersionFileURL.path) {
                try FileManager.default.removeItem(at: minimumAppVersionFileURL)
            }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(version.utf8).write(to: minimumAppVersionFileURL, options: .atomic)
    }
}
