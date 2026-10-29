// Minimum iOS 17.
//  A random ID for this installation, created once and kept in UserDefaults. It names this device's document under
//  `users/{uid}/devices`, so one account can have several devices. A reinstall gets a new one.

import Foundation

enum InstallID {
    private static let key = "installId"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: key)
        return created
    }
}
