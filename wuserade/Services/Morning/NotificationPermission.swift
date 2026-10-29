// Minimum iOS 17.
//  Whether the reader lets Wuserade show notifications. Asked only when they turn the morning poem on.
//  `SystemNotificationPermission` asks iOS; tests use a fake.

import Foundation
import UserNotifications

protocol NotificationPermission: Sendable {
    /// The current system status. Never shows a prompt.
    func status() async -> UNAuthorizationStatus
    /// Shows the system prompt if the reader has not answered it yet; true when notifications are allowed.
    func request() async -> Bool
}

struct SystemNotificationPermission: NotificationPermission {
    func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Alerts and sound only: the app shows no badge.
    func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
