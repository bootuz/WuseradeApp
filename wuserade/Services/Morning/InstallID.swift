// Minimum iOS 17.
//  A random ID for this installation, created once and kept in a file excluded from backups (`DeviceOnlyFiles`).
//  It names this device's document under `users/{uid}/devices`, so one account can have several devices. A
//  reinstall, or a backup restored onto another phone, gets a new one.

import Foundation

enum InstallID {
    private static let fileName = "installId"

    /// `directory` is the test seam; the app uses `DeviceOnlyFiles.defaultDirectory`. If the ID cannot be saved it is
    /// still returned, and the next launch makes a new one, which only registers this device again.
    static func current(directory: URL? = DeviceOnlyFiles.defaultDirectory) -> String {
        if let directory,
           let saved = DeviceOnlyFiles.read(fileName, in: directory).flatMap({ String(data: $0, encoding: .utf8) }),
           !saved.isEmpty {
            return saved
        }
        let created = UUID().uuidString
        if let directory {
            try? DeviceOnlyFiles.write(Data(created.utf8), name: fileName, in: directory)
        }
        return created
    }
}
