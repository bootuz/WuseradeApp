// Minimum iOS 17.
//  Where the day's picks come from: `daily/{YYYY-MM-DD}`, written by the server. `FirestoreDailyStore` reads it
//  with the Firestore SDK; tests use a fake.

import FirebaseFirestore
import Foundation

protocol DailyStore: Sendable {
    /// The picks for `date` (`yyyy-MM-dd`), or nil when the server has not written that day.
    func fetch(date: String) async throws -> DailyPicks?
}

struct FirestoreDailyStore: DailyStore {
    /// Resolved on every call rather than stored, so the store can be created before `FirebaseApp.configure()`
    /// has run.
    private var db: Firestore { Firestore.firestore() }

    func fetch(date: String) async throws -> DailyPicks? {
        let snapshot = try await db.collection("daily").document(date).getDocument()
        guard snapshot.exists, let fields = snapshot.data() else { return nil }
        return try Self.picks(from: fields)
    }

    /// Decodes the fields of a `daily/{date}` document. `createdAt` is ignored.
    static func picks(from fields: [String: Any]) throws -> DailyPicks {
        try Firestore.Decoder().decode(DailyPicks.self, from: fields)
    }
}
