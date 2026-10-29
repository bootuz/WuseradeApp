// Minimum iOS 17.
//  This device's morning-poem registration at `users/{uid}/devices/{installId}`, which the server's morning push
//  reads. `FirestoreDeviceRegistry` writes it with the Firestore SDK; tests use a fake.

import FirebaseFirestore
import Foundation

/// What the server needs to send this device the morning poem. `nextSendAt` is the next time it is due, by the same
/// rule as the server's (`MorningSchedule`).
struct DeviceRegistration: Equatable {
    var fcmToken: String
    /// An IANA identifier, such as "Europe/Moscow".
    var timeZone: String
    /// "HH:MM" on a 24-hour clock.
    var notifyAt: String
    var enabled: Bool
    var nextSendAt: Date
}

protocol DeviceRegistry: Sendable {
    /// Writes the whole registration of `installId` under `uid`, with `updatedAt` set to the server time.
    func upsert(_ device: DeviceRegistration, installId: String, uid: String) async throws
    /// Deletes the registration of `installId` under `uid`. Deleting one that is already gone succeeds.
    func remove(installId: String, uid: String) async throws
}

/// Each document holds exactly the six fields the security rules allow.
struct FirestoreDeviceRegistry: DeviceRegistry {
    /// Resolved on every call rather than stored, so the registry can be created before `FirebaseApp.configure()`.
    private var db: Firestore { Firestore.firestore() }

    private func document(installId: String, uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("devices").document(installId)
    }

    func upsert(_ device: DeviceRegistration, installId: String, uid: String) async throws {
        try await document(installId: installId, uid: uid).setData([
            "fcmToken": device.fcmToken,
            "timeZone": device.timeZone,
            "notifyAt": device.notifyAt,
            "enabled": device.enabled,
            "nextSendAt": Timestamp(date: device.nextSendAt),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    func remove(installId: String, uid: String) async throws {
        try await document(installId: installId, uid: uid).delete()
    }
}
