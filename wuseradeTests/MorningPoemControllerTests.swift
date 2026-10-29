import Foundation
import Testing
import UserNotifications
@testable import Wuserade

@MainActor
final class MorningPoemControllerTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own defaults suite.
    private let suiteName = "MorningPoemControllerTests-\(UUID().uuidString)"
    /// 07:00 in Moscow.
    private let now = Date(timeIntervalSince1970: 1_793_246_400) // 2026-10-29 04:00 UTC
    private var zone = TimeZone(identifier: "Europe/Moscow")!
    private var paused = false
    /// This test's device-only folder, for the registration record.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MorningPoemControllerTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func makeController(
        registry: FakeDeviceRegistry,
        permission: FakeNotificationPermission = FakeNotificationPermission()
    ) throws -> MorningPoemController {
        MorningPoemController(
            registry: registry,
            permission: permission,
            installId: "install-1",
            defaults: try defaults(),
            record: DeviceRegistrationRecord(directory: directory),
            now: { [now] in now },
            timeZone: { [unowned self] in zone },
            isPaused: { [unowned self] in paused }
        )
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 29) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func `Turning on asks permission and registers`() async throws {
        let registry = FakeDeviceRegistry()
        let permission = FakeNotificationPermission(granted: true)
        let controller = try makeController(registry: registry, permission: permission)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        #expect(!controller.enabled)
        #expect(controller.notifyAt == "08:00")
        #expect(registry.calls == [], "a device that never turned it on registers nothing")
        #expect(permission.requests == 0, "permission is asked only when the reader turns it on")

        await controller.setEnabled(true)

        #expect(permission.requests == 1)
        #expect(controller.enabled)
        #expect(!controller.permissionDenied)
        #expect(registry.calls == ["upsert install-1 alice"])
        #expect(registry.devices(for: "alice")["install-1"] == DeviceRegistration(
            fcmToken: "token-1", timeZone: "Europe/Moscow", notifyAt: "08:00", enabled: true, nextSendAt: at(5)
        ))

        // The choice is kept on the device.
        let relaunched = try makeController(registry: registry, permission: permission)
        #expect(relaunched.enabled)
        #expect(relaunched.notifyAt == "08:00")
    }

    @Test func `Refused permission keeps it off`() async throws {
        let registry = FakeDeviceRegistry()
        let permission = FakeNotificationPermission(granted: false)
        let controller = try makeController(registry: registry, permission: permission)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")

        await controller.setEnabled(true)

        #expect(permission.requests == 1)
        #expect(!controller.enabled)
        #expect(controller.permissionDenied)
        #expect(registry.calls == [])
        #expect(try !makeController(registry: registry, permission: permission).enabled)

        // Allowed in iOS Settings, then back in the app: the note goes, and turning it on now works.
        permission.setStatus(.authorized)
        await controller.refreshPermission()
        #expect(!controller.permissionDenied)
        await controller.setEnabled(true)
        #expect(controller.enabled)
        #expect(registry.calls == ["upsert install-1 alice"])
    }

    @Test func `Denied in iOS Settings while on keeps the choice and says so`() async throws {
        let registry = FakeDeviceRegistry()
        let permission = FakeNotificationPermission(granted: true)
        let controller = try makeController(registry: registry, permission: permission)
        await controller.setEnabled(true)

        permission.setStatus(.denied)
        await controller.refreshPermission()

        #expect(controller.enabled, "the reader's choice stays")
        #expect(controller.permissionDenied)
        #expect(permission.requests == 1, "checking the status never asks again")

        permission.setStatus(.authorized)
        await controller.refreshPermission()
        #expect(!controller.permissionDenied)
    }

    @Test func `Changing the time re-registers with a new nextSendAt`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        await controller.setEnabled(true)

        await controller.setTime("09:30")

        #expect(controller.notifyAt == "09:30")
        #expect(registry.calls == ["upsert install-1 alice", "upsert install-1 alice"])
        #expect(registry.devices(for: "alice")["install-1"]?.notifyAt == "09:30")
        #expect(registry.devices(for: "alice")["install-1"]?.nextSendAt == at(6, 30))

        // Not a time: ignored.
        await controller.setTime("25:00")
        #expect(controller.notifyAt == "09:30")
        #expect(registry.calls.count == 2)

        // A time before now in Moscow is tomorrow's.
        await controller.setTime("06:00")
        #expect(registry.devices(for: "alice")["install-1"]?.nextSendAt == at(3, day: 30))
    }

    @Test func `Token, time zone and account changes re-register, and nothing else does`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        await controller.setEnabled(true)
        #expect(registry.calls.count == 1)

        // Becoming active in the same zone, or the same token or account again: nothing to write. A write here
        // would push nextSendAt past a morning the server has not sent yet.
        await controller.timeZoneChanged()
        await controller.tokenChanged("token-1")
        await controller.accountChanged(uid: "alice")
        #expect(registry.calls.count == 1)

        zone = TimeZone(identifier: "Europe/Berlin")!
        await controller.timeZoneChanged()
        #expect(registry.devices(for: "alice")["install-1"]?.timeZone == "Europe/Berlin")
        #expect(registry.devices(for: "alice")["install-1"]?.nextSendAt == at(7))

        await controller.tokenChanged("token-2")
        #expect(registry.devices(for: "alice")["install-1"]?.fcmToken == "token-2")

        await controller.accountChanged(uid: "bob")
        #expect(registry.calls == [
            "upsert install-1 alice", "upsert install-1 alice", "upsert install-1 alice", "upsert install-1 bob",
        ])

        // A relaunch with the same state writes nothing either.
        let relaunched = try makeController(registry: registry)
        await relaunched.accountChanged(uid: "bob")
        await relaunched.tokenChanged("token-2")
        #expect(registry.calls.count == 4)
    }

    @Test func `Turning off registers it off`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        await controller.setEnabled(true)

        await controller.setEnabled(false)

        #expect(!controller.enabled)
        #expect(registry.calls == ["upsert install-1 alice", "upsert install-1 alice"])
        #expect(registry.devices(for: "alice")["install-1"]?.enabled == false, "the document stays, turned off")
    }

    @Test func `No uid or no token registers nothing`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry)

        await controller.setEnabled(true)
        await controller.tokenChanged("token-1")
        await controller.setTime("07:15")
        #expect(registry.calls == [], "no account")

        let other = try makeController(registry: registry)
        await other.tokenChanged(nil)
        await other.accountChanged(uid: "alice")
        await other.setTime("07:30")
        #expect(registry.calls == [], "no token")

        // Both known: it registers.
        await other.tokenChanged("token-1")
        #expect(registry.calls == ["upsert install-1 alice"])

        // Signed out entirely: nothing more.
        await other.accountChanged(uid: nil)
        await other.setTime("07:45")
        #expect(registry.calls == ["upsert install-1 alice"])
    }

    @Test func `Nothing is written while an account operation runs`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")

        paused = true
        await controller.setEnabled(true)
        await controller.setTime("09:00")
        await controller.tokenChanged("token-2")
        await controller.accountChanged(uid: "bob")
        #expect(registry.calls == [])
        #expect(controller.enabled, "the choice is kept while paused")

        // The operation ends and the app reports the resulting account: it registers there.
        paused = false
        await controller.accountChanged(uid: "bob")
        #expect(registry.calls == ["upsert install-1 bob"])
        #expect(registry.devices(for: "bob")["install-1"] == DeviceRegistration(
            fcmToken: "token-2", timeZone: "Europe/Moscow", notifyAt: "09:00", enabled: true, nextSendAt: at(6)
        ))
    }

    @Test func `A forgotten registration is written again for the same account`() async throws {
        let registry = FakeDeviceRegistry()
        let record = DeviceRegistrationRecord(directory: directory)
        let controller = MorningPoemController(
            registry: registry, permission: FakeNotificationPermission(), installId: "install-1",
            defaults: try defaults(), record: record, now: { [now] in now }, timeZone: { [unowned self] in zone }
        )
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        await controller.setEnabled(true)

        record.forget(uid: "bob")
        await controller.accountChanged(uid: "alice")
        #expect(registry.calls.count == 1, "forgetting another account changes nothing")

        record.forget(uid: "alice")
        await controller.accountChanged(uid: "alice")
        #expect(registry.calls == ["upsert install-1 alice", "upsert install-1 alice"])
    }

    @Test func `A failed write is tried again on the next change`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry)
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        registry.setUpsertError(FakeDeviceRegistry.Failure())

        await controller.setEnabled(true)
        #expect(controller.enabled)
        #expect(registry.devices(for: "alice").isEmpty)

        registry.setUpsertError(nil)
        await controller.timeZoneChanged()
        #expect(registry.devices(for: "alice")["install-1"]?.enabled == true)
    }

    @Test func `A deleted account turns it off and the next account registers nothing`() async throws {
        let registry = FakeDeviceRegistry()
        let controller = try makeController(registry: registry, permission: FakeNotificationPermission(granted: true))
        await controller.accountChanged(uid: "alice")
        await controller.tokenChanged("token-1")
        await controller.setEnabled(true)
        let record = DeviceRegistrationRecord(directory: directory)
        // The account forgets the registration before deleting it, as `AccountManager` does.
        record.forget(uid: "alice")

        controller.accountDeleted()
        await controller.accountChanged(uid: "anon-1")
        await controller.setTime("07:30")
        await controller.timeZoneChanged()

        #expect(!controller.enabled)
        #expect(registry.calls == ["upsert install-1 alice"], "nothing is written for the new account")
        #expect(!(try makeController(registry: registry).enabled), "it stays off after a relaunch")
    }
}
