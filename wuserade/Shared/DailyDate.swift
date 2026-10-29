// Minimum iOS 17.
//  The id of a daily document: the reader's local calendar date as `yyyy-MM-dd`, in the Gregorian calendar
//  whatever the device's own calendar.

import Foundation

enum DailyDate {
    static func string(for date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
