import FirebaseFirestore
import Foundation

/// Reads content documents written by the admin tool:
/// `meta/content`, `catalog/{index}` and `poems/{id}`.
struct FirestoreContentRepository: ContentRepository {
    /// `meta/content` does not exist. A failed read, not a cleared minimum app version.
    struct MissingMeta: LocalizedError {
        var errorDescription: String? { "meta/content does not exist." }
    }

    /// Resolved on every call rather than stored, so the repository can be created
    /// before `FirebaseApp.configure()` has run.
    private var db: Firestore { Firestore.firestore() }

    func fetchMeta() async throws -> MetaDocument {
        let snapshot = try await db.collection("meta").document("content").getDocument()
        guard let fields = snapshot.data() else { throw MissingMeta() }
        return MetaDocument(fields: fields)
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

extension MetaDocument {
    /// Builds from the raw fields of `meta/content`. `minimumAppVersion` is read on its own,
    /// so it comes through even when the rest of the document does not decode.
    init(fields: [String: Any]) {
        minimumAppVersion = fields["minimumAppVersion"] as? String
        meta = Result { try Firestore.Decoder().decode(ContentMeta.self, from: fields) }
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
