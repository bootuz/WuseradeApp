// Minimum iOS 17.
//  The widgets' timeline without WidgetKit's side: the REST address of a day's document, decoding it, the
//  entries up to the next local midnight, and the parts of a poem a widget has room for.

import Foundation

enum DailyTimeline {
    /// `daily/{date}` on Firestore's REST API. Daily documents are public, so the widget reads them without
    /// Firebase or a sign-in.
    static func restURL(date: String) -> URL {
        // A fixed address and a `yyyy-MM-dd` id: never nil.
        URL(string: "https://firestore.googleapis.com/v1/projects/wuserade/databases/(default)/documents/daily/\(date)")!
    }

    /// The picks in a REST response body. Throws for anything else, such as an error body.
    static func picks(fromREST data: Data) throws -> DailyPicks {
        try FirestoreREST.decode(DailyPicks.self, from: data)
    }

    /// The picks now, then nothing from the next local midnight, so the widget reads the new day's document.
    static func entries(for picks: DailyPicks?, now: Date, timeZone: TimeZone) -> [DailyEntry] {
        [
            DailyEntry(date: now, picks: picks),
            DailyEntry(date: nextMidnight(after: now, in: timeZone), picks: nil),
        ]
    }

    /// The start of the next local day.
    static func nextMidnight(after date: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? date.addingTimeInterval(86_400)
    }

    /// '29.10' for '2026-10-29', whatever the device's region; nil when `date` is not `yyyy-MM-dd`.
    static func dayAndMonth(of date: String) -> String? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return "\(parts[2]).\(parts[1])"
    }

    /// Up to `limit` lines of the first stanza, without the poet's indent. Blank lines before it are skipped.
    static func openingLines(of text: String, limit: Int) -> [String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return Array(lines.drop { $0.isEmpty }.prefix { !$0.isEmpty }.prefix(limit))
    }
}
