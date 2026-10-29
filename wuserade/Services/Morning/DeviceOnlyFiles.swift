// Minimum iOS 17.
//  Small files that belong to this device only: a folder in Application Support excluded from iCloud and computer
//  backups, so a restore onto another phone never brings them along. The install ID and the last morning-poem
//  registration live here; two phones sharing them would share one device document.

import Foundation

enum DeviceOnlyFiles {
    /// Application Support/DeviceOnly. Nil only if the system has no Application Support folder.
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DeviceOnly", isDirectory: true)
    }

    static func read(_ name: String, in directory: URL) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// Writes atomically, creating the folder if needed, and marks both excluded from backup. A failure is thrown.
    static func write(_ data: Data, name: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        let file = directory.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        // An atomic write replaces the file, so it is marked after every write.
        try excludeFromBackup(file)
    }

    static func remove(_ name: String, in directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try url.setResourceValues(values)
    }
}
