// Minimum iOS 17.
//  The interface language. iOS keeps the per-app language from its Settings app in AppleLanguages in the app's
//  own defaults, and Settings' Language row opens that page. Until the reader picks one there, it is Kabardian.

import Foundation

enum AppLanguage {
    private static let key = "AppleLanguages"
    private static let kabardian = "kbd"
    private static let defaultAppliedKey = "languageDefaultApplied"

    /// The app's own list, not the device's: `UserDefaults.standard` would fall back to the global domain.
    private static var stored: [String]? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: id)?[key] as? [String]
    }

    /// Kabardian on the first launch, whatever the device language. Only once: choosing the device's own language
    /// in the iOS Settings app removes the stored list, and that choice must stick.
    static func applyDefault() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultAppliedKey) else { return }
        defaults.set(true, forKey: defaultAppliedKey)
        if stored == nil {
            defaults.set([kabardian], forKey: key)
        }
    }
}
