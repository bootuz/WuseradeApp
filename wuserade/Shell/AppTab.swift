// Minimum iOS 17.
//  The five places of the app. Compact width hides Зытеухуар (Home shows the themes as a section) and titles
//  the first tab Усэхэр; regular width titles it УсэщӀэхэр.

import Foundation

enum AppTab: String, Hashable, CaseIterable {
    case new, themes, poets, liked, search

    func title(compact: Bool) -> String {
        switch self {
        case .new: compact ? String(localized: "Усэхэр") : String(localized: "УсэщӀэхэр")
        case .themes: String(localized: "Зытеухуар")
        case .poets: String(localized: "УсакӀуэхэр")
        case .liked: String(localized: "Сигу ирихьахэр")
        case .search: String(localized: "ЛъыхъуапӀэ")
        }
    }

    /// Outline names: the tab bar fills them itself, and the sidebar shows them in outline.
    var symbol: String {
        switch self {
        case .new: "text.book.closed"
        case .themes: "books.vertical"
        case .poets: "person.2"
        case .liked: "heart"
        case .search: "magnifyingglass"
        }
    }
}
