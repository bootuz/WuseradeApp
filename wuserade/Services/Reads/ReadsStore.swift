// Minimum iOS 17.
//  The reader's reading history at `users/{uid}/reads/{poemId}`, which the server's suggestions skip.
//  `FirestoreReadsStore` writes it with the Firestore SDK; tests use a fake.

import FirebaseFirestore
import Foundation
import os

protocol ReadsStore: Sendable {
    /// Records that `uid` read the poem. A read that already exists counts as written.
    func markRead(poemId: Int, uid: String) async throws
    /// The IDs of every poem `uid` has read, confirmed by the server. Lists only the user's own reads.
    func fetchReadIDs(uid: String) async throws -> [Int]
    /// Deletes `users/{uid}/reads/*`. Safe to run again after a partial failure.
    func deleteAllReads(uid: String) async throws
}

/// Each read is `{poemId, readAt}`, exactly what the security rules allow. The rules allow creating a read but
/// never updating it, so writing one that already exists is refused; that refusal means the read is there.
struct FirestoreReadsStore: ReadsStore {
    /// Firestore allows at most 500 writes in one batch.
    private static let batchLimit = 500

    /// Resolved on every call rather than stored, so the store can be created before `FirebaseApp.configure()`.
    private var db: Firestore { Firestore.firestore() }

    private func readsCollection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("reads")
    }

    func markRead(poemId: Int, uid: String) async throws {
        do {
            try await readsCollection(uid).document(String(poemId)).setData([
                "poemId": poemId,
                "readAt": FieldValue.serverTimestamp(),
            ])
        } catch let error as NSError
            where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            // The create rule refuses a second write of the same read: it already exists.
        }
    }

    /// Server-confirmed, so the account switch never deletes anonymous reads it read from an incomplete offline
    /// cache. Offline it throws instead.
    func fetchReadIDs(uid: String) async throws -> [Int] {
        let snapshot = try await readsCollection(uid).getDocuments(source: .server)
        return snapshot.documents.compactMap { document in
            guard let id = Int(document.documentID) else {
                Self.logger.error("Skipping read \(document.reference.path, privacy: .public)")
                return nil
            }
            return id
        }
    }

    /// Deleting documents that are already gone succeeds, so a retry after a partial failure finishes the job.
    func deleteAllReads(uid: String) async throws {
        let documents = try await readsCollection(uid).getDocuments(source: .server).documents.map(\.reference)
        for start in stride(from: 0, to: documents.count, by: Self.batchLimit) {
            let batch = db.batch()
            for document in documents[start ..< min(start + Self.batchLimit, documents.count)] {
                batch.deleteDocument(document)
            }
            try await batch.commit()
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "FirestoreReadsStore"
    )
}
