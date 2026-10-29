// Minimum iOS 17.
//  Where a reader's poet photo goes: a file in Storage and the waiting record in Firestore. The app talks to
//  them through `FirebasePhotoSubmissionStore`; tests substitute an in-memory fake.

import Foundation

protocol PhotoSubmissionStore: Sendable {
    /// Whether `photoSubmissions/{authorId}_{uid}` exists.
    func isWaiting(authorId: Int, uid: String) async throws -> Bool
    /// Uploads the JPEG, then writes the waiting record.
    func send(_ jpeg: Data, authorId: Int, uid: String) async throws
    /// Deletes the file, then the record. Something that is already gone counts as deleted.
    func delete(authorId: Int, uid: String) async throws
}
