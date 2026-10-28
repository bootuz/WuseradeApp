import FirebaseFirestore
import Foundation

/// Reads content documents written by the admin tool:
/// `meta/content`, `catalog/{index}` and `poems/{id}`.
struct FirestoreContentRepository: ContentRepository {
    /// Resolved on every call rather than stored, so the repository can be created
    /// before `FirebaseApp.configure()` has run.
    private var db: Firestore { Firestore.firestore() }

    func fetchMeta() async throws -> ContentMeta {
        try await db.collection("meta").document("content").getDocument(as: ContentMeta.self)
    }

    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk {
        try await db.collection("catalog").document(String(index)).getDocument(as: CatalogChunk.self)
    }

    func fetchPoem(id: Int) async throws -> Poem {
        let record = try await db.collection("poems").document(String(id)).getDocument(as: PoemRecord.self)
        return Poem(
            id: record.id,
            title: record.title,
            author: Author(id: record.authorId, name: record.authorName),
            content: record.text
        )
    }
}

/// The subset of a `poems/{id}` document the reader needs. The other stored fields
/// (`themeId`, `createdAt`, `updatedAt`, `submittedBy`) are ignored.
private struct PoemRecord: Decodable {
    let id: Int
    let title: String
    let text: String
    let authorId: Int
    let authorName: String
}
