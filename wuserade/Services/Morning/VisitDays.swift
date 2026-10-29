// Minimum iOS 17.
//  The last three distinct days the reader opened the app, as `DailyDate` strings in their time zone, and whether
//  they have answered the morning-poem invitation. Kept in UserDefaults; Home observes both keys.

import Foundation

struct VisitDays {
    /// Plain keys without dots, so `@AppStorage` can observe them.
    enum Keys {
        static let days = "visitDays"
        static let invitationDone = "morningInvitationDone"
    }

    private static let kept = 3

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Oldest first, comma-separated in one string so that it can be observed.
    private var days: [String] {
        get { (defaults.string(forKey: Keys.days) ?? "").split(separator: ",").map(String.init) }
        nonmutating set { defaults.set(newValue.joined(separator: ","), forKey: Keys.days) }
    }

    /// Records the day `date` falls on. The same day twice is one visit; only the last three days are kept.
    mutating func record(_ date: Date, in timeZone: TimeZone = .current) {
        let day = DailyDate.string(for: date, in: timeZone)
        var days = days
        guard !days.contains(day) else { return }
        days.append(day)
        self.days = Array(days.suffix(Self.kept))
    }

    var count: Int { days.count }

    var invitationDone: Bool {
        get { defaults.bool(forKey: Keys.invitationDone) }
        set { defaults.set(newValue, forKey: Keys.invitationDone) }
    }
}
