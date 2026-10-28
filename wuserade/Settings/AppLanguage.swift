// Minimum iOS 17.
//  The interface languages. The choice is kept where iOS keeps the per-app language from Settings
//  (AppleLanguages in the app's own defaults), so the two stay in sync. It takes effect on the next launch.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case kabardian = "kbd"
    case english = "en"
    case russian = "ru"
    case turkish = "tr"
    case arabic = "ar"

    var id: String { rawValue }

    /// Each language named in itself, so a reader finds theirs whatever the interface is showing.
    var name: String {
        switch self {
        case .kabardian: "Адыгэбзэ"
        case .english: "English"
        case .russian: "Русский"
        case .turkish: "Türkçe"
        case .arabic: "العربية"
        }
    }

    private static let key = "AppleLanguages"

    /// The app's own list, not the device's: `UserDefaults.standard` would fall back to the global domain.
    private static var stored: [String]? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: id)?[key] as? [String]
    }

    /// The language for the next launch, chosen here or in the iOS Settings app.
    static var selected: AppLanguage {
        get { stored?.first.flatMap(matching) ?? .kabardian }
        set { UserDefaults.standard.set([newValue.rawValue], forKey: key) }
    }

    /// The language the interface is showing in this launch.
    static var current: AppLanguage {
        Bundle.main.preferredLocalizations.first.flatMap(matching) ?? .kabardian
    }

    /// Kabardian whatever the device language, until the reader picks another.
    static func applyDefault() {
        if stored == nil {
            selected = .kabardian
        }
    }

    /// 'en-GB' is English and 'ru-RU' Russian.
    private static func matching(_ identifier: String) -> AppLanguage? {
        allCases.first { identifier == $0.rawValue || identifier.hasPrefix($0.rawValue + "-") }
    }
}
