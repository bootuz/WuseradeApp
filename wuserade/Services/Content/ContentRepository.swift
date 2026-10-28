import Foundation

/// Source of poetry content. The app talks to Firestore through `FirestoreContentRepository`;
/// tests substitute an in-memory fake so nothing touches the network.
protocol ContentRepository: Sendable {
    /// Reads `meta/content`: the minimum app version, the catalog version and the author and theme lists.
    /// Throws only when the document cannot be read at all.
    func fetchMeta() async throws -> MetaDocument
    /// Reads `catalog/{index}`: one slice of the poem catalog.
    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk
    /// Reads `poems/{id}`: a single poem with its full text.
    func fetchPoem(id: Int) async throws -> Poem
}
