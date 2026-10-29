// Minimum iOS 17.
//  Stores a waiting photo at `photo-submissions/{authorId}/{uid}.jpg` in Storage and its record at
//  `photoSubmissions/{authorId}_{uid}` in Firestore. Both hold exactly what the security rules allow.

import FirebaseFirestore
import FirebaseStorage
import Foundation

struct FirebasePhotoSubmissionStore: PhotoSubmissionStore {
    /// How long Storage keeps retrying a failed upload or other operation. The SDK default for an upload is
    /// 600 seconds, and a send on a dead network would hold the sheet that long before showing "try again".
    static let retryTime: TimeInterval = 60

    /// Resolved on every call rather than stored, so the store can be created before
    /// `FirebaseApp.configure()` has run. The shared instance is set to give up after `retryTime`.
    var storage: Storage {
        let storage = Storage.storage()
        storage.maxUploadRetryTime = Self.retryTime
        storage.maxOperationRetryTime = Self.retryTime
        return storage
    }
    private var db: Firestore { Firestore.firestore() }

    private func file(authorId: Int, uid: String) -> StorageReference {
        storage.reference(withPath: "photo-submissions/\(authorId)/\(uid).jpg")
    }

    private func record(authorId: Int, uid: String) -> DocumentReference {
        db.collection("photoSubmissions").document("\(authorId)_\(uid)")
    }

    func isWaiting(authorId: Int, uid: String) async throws -> Bool {
        try await record(authorId: authorId, uid: uid).getDocument().exists
    }

    /// The file first, then the record. If the record fails, the file stays; sending again replaces it.
    /// Only here can a refusal mean "blocked from sending photos", so only here it becomes `.banned`:
    /// the rules for reading and deleting ignore the `photoBan` claim.
    func send(_ jpeg: Data, authorId: Int, uid: String) async throws {
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await file(authorId: authorId, uid: uid).putDataAsync(jpeg, metadata: metadata)
            try await record(authorId: authorId, uid: uid).setData([
                "authorId": authorId,
                "submittedBy": uid,
                "createdAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            throw Self.mapped(error)
        }
    }

    /// The file first, then the record. A missing file is skipped (the record may be all that is left
    /// after an earlier attempt), and deleting a record that is already gone succeeds.
    func delete(authorId: Int, uid: String) async throws {
        do {
            try await file(authorId: authorId, uid: uid).delete()
        } catch where Self.isNotFound(error) {
            // Nothing to delete.
        }
        try await record(authorId: authorId, uid: uid).delete()
    }

    /// What `send` throws. A Storage `unauthorized` or a Firestore `permissionDenied` means the rules refused
    /// the reader (blocked from sending photos). Anything else passes through unchanged.
    static func mapped(_ error: Error) -> Error {
        let nsError = error as NSError
        let isStorageDenied = nsError.domain == StorageErrorDomain
            && nsError.code == StorageErrorCode.unauthorized.rawValue
        let isFirestoreDenied = nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
        return isStorageDenied || isFirestoreDenied ? PhotoSubmissionError.banned : error
    }

    /// True when Storage says the file does not exist.
    static func isNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == StorageErrorDomain && nsError.code == StorageErrorCode.objectNotFound.rawValue
    }
}
