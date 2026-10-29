import Foundation
import Testing
@testable import Wuserade

/// The install ID and the last morning-poem registration stay on this device: they are kept in a folder excluded
/// from backups, so a backup restored onto another phone registers that phone as a new device.
@MainActor
final class InstallIDTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("InstallIDTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        let excluded = try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        // `as Bool?` asks #require to unwrap the optional rather than test it as a condition.
        return try #require(excluded as Bool?)
    }

    @Test func `A missing ID is created once and then kept`() throws {
        let first = InstallID.current(directory: directory)
        #expect(UUID(uuidString: first) != nil)
        #expect(first.count <= 64, "the rules allow install IDs up to 64 characters")
        #expect(InstallID.current(directory: directory) == first)

        // Kept out of backups, folder and file.
        #expect(try isExcludedFromBackup(directory))
        #expect(try isExcludedFromBackup(directory.appendingPathComponent("installId")))

        // Another device (another folder) gets its own.
        let other = directory.appendingPathComponent("other", isDirectory: true)
        #expect(InstallID.current(directory: other) != first)
    }

    @Test func `The ID does not come from UserDefaults`() throws {
        // An ID an older build kept in UserDefaults is restored with a backup, so it is not used.
        let suiteName = "InstallIDTests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("restored-id", forKey: "installId")

        #expect(InstallID.current(directory: directory) != "restored-id")
    }

    @Test func `The registration record is kept on disk, out of backups, and forgotten per account`() throws {
        let entry = DeviceRegistrationRecord.Entry(
            uid: "alice", fcmToken: "token-1", timeZone: "Europe/Moscow", notifyAt: "08:00", enabled: true
        )
        let record = DeviceRegistrationRecord(directory: directory)
        #expect(record.last == nil)
        record.last = entry

        let relaunched = DeviceRegistrationRecord(directory: directory)
        #expect(relaunched.last == entry)
        #expect(try isExcludedFromBackup(directory.appendingPathComponent("morningPoemRegistration")))

        relaunched.forget(uid: "bob")
        #expect(relaunched.last == entry)
        relaunched.forget(uid: "alice")
        #expect(relaunched.last == nil)
        #expect(DeviceRegistrationRecord(directory: directory).last == nil)
    }
}
