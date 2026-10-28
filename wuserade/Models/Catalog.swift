import Foundation

/// One `catalog/{n}` Firestore document.
struct CatalogChunk: Codable {
    let version: Int
    let entries: [PoemSummary]
}

/// The whole catalog, assembled from every chunk at a single `version`.
struct Catalog: Codable, Equatable {
    let version: Int
    let entries: [PoemSummary]

    func newestFirst() -> [PoemSummary] {
        Self.sortedNewestFirst(entries)
    }

    func poems(byAuthor id: Int) -> [PoemSummary] {
        Self.sortedNewestFirst(entries.filter { $0.authorId == id })
    }

    func poems(inTheme id: Int) -> [PoemSummary] {
        Self.sortedNewestFirst(entries.filter { $0.themeId == id })
    }

    /// Newest first by `createdAt`; poems created at the same instant fall back to the higher id first,
    /// so the order is stable regardless of the order chunks were read in.
    private static func sortedNewestFirst(_ poems: [PoemSummary]) -> [PoemSummary] {
        poems.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id > $1.id
        }
    }
}
