import FirebaseFirestore
import Foundation
import os

/// Per-account likes and the account's user document. The app talks to Firestore through
/// `FirestoreLikesStore`; tests substitute an in-memory fake.
protocol LikesStore: Sendable {
    /// Reads every like of `uid`, newest first, confirmed by the server.
    func fetchLikes(uid: String) async throws -> [Like]
    /// Emits the likes of `uid`, newest first, now and after every change. Cancelling the
    /// iteration stops listening.
    func observeLikes(uid: String) -> AsyncThrowingStream<[Like], Error>
    func setLike(_ like: Like, uid: String) async throws
    func setLikes(_ likes: [Like], uid: String) async throws
    func removeLike(poemId: Int, uid: String) async throws
    /// Creates `users/{uid}` with `createdAt` when it does not exist yet. Never overwrites it.
    func ensureUserDocument(uid: String) async throws
    /// Deletes `users/{uid}/likes/*` and `users/{uid}`. Safe to run again after a partial failure.
    func deleteAllData(uid: String) async throws
}

/// Stores likes at `users/{uid}/likes/{poemId}` and the account at `users/{uid}`.
/// The documents hold exactly the fields the security rules allow.
struct FirestoreLikesStore: LikesStore {
    /// Firestore allows at most 500 writes in one batch.
    private static let batchLimit = 500

    /// Resolved on every call rather than stored, so the store can be created before
    /// `FirebaseApp.configure()` has run.
    private var db: Firestore { Firestore.firestore() }

    private func userDocument(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func likesCollection(_ uid: String) -> CollectionReference {
        userDocument(uid).collection("likes")
    }

    private func likeDocument(poemId: Int, uid: String) -> DocumentReference {
        likesCollection(uid).document(String(poemId))
    }

    /// Server-confirmed, so the "credential already in use" flow never deletes anonymous
    /// likes it read from an incomplete offline cache. Offline it throws instead.
    func fetchLikes(uid: String) async throws -> [Like] {
        let snapshot = try await likesCollection(uid)
            .order(by: "likedAt", descending: true)
            .getDocuments(source: .server)
        return Self.likes(in: snapshot)
    }

    func observeLikes(uid: String) -> AsyncThrowingStream<[Like], Error> {
        let query = likesCollection(uid).order(by: "likedAt", descending: true)
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                } else if let snapshot {
                    continuation.yield(Self.likes(in: snapshot))
                }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func setLike(_ like: Like, uid: String) async throws {
        try await likeDocument(poemId: like.poemId, uid: uid).setData(Firestore.Encoder().encode(like))
    }

    func setLikes(_ likes: [Like], uid: String) async throws {
        let encoder = Firestore.Encoder()
        for start in stride(from: 0, to: likes.count, by: Self.batchLimit) {
            let batch = db.batch()
            for like in likes[start ..< min(start + Self.batchLimit, likes.count)] {
                batch.setData(try encoder.encode(like), forDocument: likeDocument(poemId: like.poemId, uid: uid))
            }
            try await batch.commit()
        }
    }

    func removeLike(poemId: Int, uid: String) async throws {
        try await likeDocument(poemId: poemId, uid: uid).delete()
    }

    /// Checks the server first, so an existing `createdAt` is never overwritten. Offline the
    /// check throws and nothing is written; the next `AccountManager.start()` tries again.
    func ensureUserDocument(uid: String) async throws {
        let document = userDocument(uid)
        guard try await !document.getDocument(source: .server).exists else { return }
        // Only `createdAt`: the rules allow an optional `displayName`, which is left out rather than null.
        try await document.setData(["createdAt": FieldValue.serverTimestamp()])
    }

    /// Reads the like documents from the server and deletes them in batches, the user document
    /// with the last batch. Deleting documents that are already gone succeeds, so a retry after
    /// a partial failure finishes the job.
    func deleteAllData(uid: String) async throws {
        let likeDocuments = try await likesCollection(uid).getDocuments(source: .server).documents.map(\.reference)
        let writes = likeDocuments + [userDocument(uid)]
        for start in stride(from: 0, to: writes.count, by: Self.batchLimit) {
            let batch = db.batch()
            for document in writes[start ..< min(start + Self.batchLimit, writes.count)] {
                batch.deleteDocument(document)
            }
            try await batch.commit()
        }
    }

    /// Skips (and logs) a document that does not decode instead of failing the whole list.
    private static func likes(in snapshot: QuerySnapshot) -> [Like] {
        snapshot.documents.compactMap { document in
            do {
                return try document.data(as: Like.self)
            } catch {
                logger.error("Skipping like \(document.reference.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "FirestoreLikesStore"
    )
}
