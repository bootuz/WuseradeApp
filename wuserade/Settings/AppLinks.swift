// Minimum iOS 17.
//  Addresses Settings opens.

import Foundation

enum AppLinks {
    static let review = URL(string: "https://itunes.apple.com/app/id6478048644?action=write-review")!
    static let appStore = URL(string: "https://apps.apple.com/app/id6478048644")!
    static let share = URL(string: "https://apple.co/3OWuu5b")!
    static let telegram = URL(string: "https://t.me/nart_kenobi")!
    static let instagram = URL(string: "https://www.instagram.com/astemirboziy")!
    static let email = URL(string: "mailto:astemirboziy@gmail.com")!
    /// The hosted privacy page, on Firebase Hosting.
    static let privacy: URL? = URL(string: "https://wuserade.com/privacy")
}
