import Foundation

/// Source of poetry content. The app talks to Firestore through `FirestoreContentRepository`;
/// tests substitute an in-memory fake so nothing touches the network.
protocol ContentRepository: Sendable {
    /// Reads `meta/content`: the catalog version plus the author and theme lists.
    func fetchMeta() async throws -> ContentMeta
    /// Reads `catalog/{index}`: one slice of the poem catalog.
    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk
    /// Reads `poems/{id}`: a single poem with its full text.
    func fetchPoem(id: Int) async throws -> Poem
}
