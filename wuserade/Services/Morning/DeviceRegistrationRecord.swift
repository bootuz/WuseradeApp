// Minimum iOS 17.
//  The morning-poem registration this device last wrote, kept in a file excluded from backups (`DeviceOnlyFiles`).
//  `MorningPoemController` skips writing the same registration twice; `AccountManager` makes it forget the one under
//  an account it removes the device from, so the next report of that account writes it again.

import Foundation

/// Not thread-safe: the controller and the account manager both use it on the main actor.
final class DeviceRegistrationRecord {
    /// What a registration depends on, besides the time it is written.
    struct Entry: Codable, Equatable {
        let uid: String
        let fcmToken: String
        let timeZone: String
        let notifyAt: String
        let enabled: Bool
    }

    private static let fileName = "morningPoemRegistration"
    /// Nil keeps it in memory only (no Application Support folder).
    private let directory: URL?
    private var cached: Entry??

    /// `directory` is the test seam; the app uses `DeviceOnlyFiles.defaultDirectory`.
    init(directory: URL? = DeviceOnlyFiles.defaultDirectory) {
        self.directory = directory
    }

    /// The registration last written, or nil when none is known.
    var last: Entry? {
        get {
            if let cached { return cached }
            let loaded = directory
                .flatMap { DeviceOnlyFiles.read(Self.fileName, in: $0) }
                .flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
            cached = .some(loaded)
            return loaded
        }
        set {
            cached = .some(newValue)
            guard let directory else { return }
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                try? DeviceOnlyFiles.write(data, name: Self.fileName, in: directory)
            } else {
                DeviceOnlyFiles.remove(Self.fileName, in: directory)
            }
        }
    }

    /// Forgets the registration under `uid`, whose device document was (or is being) removed.
    func forget(uid: String) {
        if last?.uid == uid { last = nil }
    }
}
