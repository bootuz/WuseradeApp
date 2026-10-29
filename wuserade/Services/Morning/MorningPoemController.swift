// Minimum iOS 17.
//  The morning poem setting: on or off and the time, kept on the device, and this device's registration under the
//  current account (`users/{uid}/devices/{installId}`), which the server's morning push reads.
//  Permission is asked only when the reader turns it on. Nothing is written while `isPaused` says so.

import Foundation
import Observation
import os
import UserNotifications

@MainActor
@Observable
final class MorningPoemController {
    /// The reader's choice. It stays on when notifications are later turned off in iOS Settings.
    private(set) var enabled: Bool
    /// "HH:MM" on a 24-hour clock, in the device's time zone.
    private(set) var notifyAt: String
    /// True when iOS does not allow Wuserade's notifications although the reader wants the morning poem, or just
    /// tried to turn it on and was refused. Settings then says so and links to iOS Settings.
    private(set) var permissionDenied = false

    @ObservationIgnored private let registry: any DeviceRegistry
    @ObservationIgnored private let permission: any NotificationPermission
    @ObservationIgnored private let installId: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    /// True while an account operation runs: a registration written then could land on an account being left or
    /// deleted, and the server would keep sending to it. The app reports the resulting account afterwards.
    @ObservationIgnored private let isPaused: @MainActor () -> Bool
    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var token: String?

    init(
        registry: any DeviceRegistry,
        permission: any NotificationPermission,
        installId: String,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current },
        isPaused: @escaping @MainActor () -> Bool = { false }
    ) {
        self.registry = registry
        self.permission = permission
        self.installId = installId
        self.defaults = defaults
        self.now = now
        self.timeZone = timeZone
        self.isPaused = isPaused
        enabled = defaults.bool(forKey: Keys.enabled)
        notifyAt = defaults.string(forKey: Keys.notifyAt).flatMap { MorningSchedule.parse($0) == nil ? nil : $0 }
            ?? Self.defaultTime
    }

    static let defaultTime = "08:00"

    /// Turning it on asks for permission first; when that is refused it stays off and `permissionDenied` is set.
    func setEnabled(_ on: Bool) async {
        if on {
            guard await permission.request() else {
                permissionDenied = true
                store(enabled: false)
                return
            }
        }
        permissionDenied = false
        store(enabled: on)
        await register()
    }

    /// Ignores anything that is not an "HH:MM" time.
    func setTime(_ hhmm: String) async {
        guard MorningSchedule.parse(hhmm) != nil else { return }
        notifyAt = hhmm
        defaults.set(hhmm, forKey: Keys.notifyAt)
        await register()
    }

    func tokenChanged(_ token: String?) async {
        self.token = token
        await register()
    }

    /// The current account, or nil without one. The app also calls it when an account operation ends.
    func accountChanged(uid: String?) async {
        self.uid = uid
        await register()
    }

    /// The device's time zone may have changed. The app calls it on the system's change and on becoming active.
    func timeZoneChanged() async {
        await register()
    }

    /// Reads the system status again, without asking. The app calls it on becoming active.
    func refreshPermission() async {
        let denied = await permission.status() == .denied
        permissionDenied = denied && (enabled || permissionDenied)
    }

    private func store(enabled: Bool) {
        self.enabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
    }

    /// Writes this device's registration when it differs from the last one written, so a launch or a return to the
    /// app writes nothing new: a fresh `nextSendAt` then could skip a morning the server has not sent yet. A device
    /// that never turned it on, or whose last registration under this account is already off, writes nothing.
    private func register() async {
        guard !isPaused(), let uid, let token else { return }
        let zone = timeZone()
        let state = Registered(uid: uid, fcmToken: token, timeZone: zone.identifier, notifyAt: notifyAt, enabled: enabled)
        let last = lastRegistered
        guard state != last else { return }
        if !enabled, last?.uid != uid || last?.enabled != true { return }

        let device = DeviceRegistration(
            fcmToken: token,
            timeZone: zone.identifier,
            notifyAt: notifyAt,
            enabled: enabled,
            nextSendAt: MorningSchedule.nextSendAt(timeZone: zone, notifyAt: notifyAt, after: now())
        )
        // Recorded before the write, so a change arriving meanwhile is compared with what is being written.
        lastRegistered = state
        do {
            try await registry.upsert(device, installId: installId, uid: uid)
        } catch {
            Self.logger.error("Could not register for the morning poem: \(error.localizedDescription, privacy: .public)")
            // The next change tries again, unless a newer registration was written meanwhile.
            if lastRegistered == state { lastRegistered = last }
        }
    }

    /// The registration last written, kept across launches.
    private var lastRegistered: Registered? {
        get { defaults.data(forKey: Keys.registered).flatMap { try? JSONDecoder().decode(Registered.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.registered) }
    }

    /// What a registration depends on, besides the time it is written.
    private struct Registered: Codable, Equatable {
        let uid: String
        let fcmToken: String
        let timeZone: String
        let notifyAt: String
        let enabled: Bool
    }

    private enum Keys {
        static let enabled = "morningPoem.enabled"
        static let notifyAt = "morningPoem.notifyAt"
        static let registered = "morningPoem.registered"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "MorningPoemController"
    )
}
