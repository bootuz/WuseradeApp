// Minimum iOS 17.
//  When a device is next due for the morning poem. The same rule as the server's `next_send_at`
//  (firebase/functions/wuserade_daily/morning.py), with the same tests: keep the two in step.

import Foundation

enum MorningSchedule {
    /// The first instant strictly after `after` at which `timeZone`'s clock reads `notifyAt` ("HH:MM").
    ///
    /// A local time skipped by a daylight-saving change moves forward by the gap (02:30 becomes 03:30). A repeated
    /// local time uses its first occurrence. Both are what Python's `fold=0` does on the server. A `notifyAt` that
    /// is not a time counts as "08:00"; the app never stores one.
    static func nextSendAt(timeZone: TimeZone, notifyAt: String, after: Date) -> Date {
        let (hour, minute) = parse(notifyAt) ?? (8, 0)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let day = local.dateComponents([.year, .month, .day], from: after)
        for offset in -1 ... 2 {
            // The wall-clock time, written as if it were UTC, then shifted by the zone's offset.
            guard let wallClock = utc.date(from: DateComponents(
                year: day.year, month: day.month, day: (day.day ?? 1) + offset, hour: hour, minute: minute
            )) else { continue }
            let candidate = instant(ofWallClock: wallClock, in: timeZone)
            if candidate > after { return candidate }
        }
        // Unreachable: one of four consecutive days always has the time after `after`.
        return after.addingTimeInterval(24 * 60 * 60)
    }

    /// The instant at which `timeZone`'s clock reads `wallClock` (given as if it were UTC), using the offset in force
    /// before a change when the time is repeated or skipped, as `fold=0` does.
    private static func instant(ofWallClock wallClock: Date, in timeZone: TimeZone) -> Date {
        let day: TimeInterval = 24 * 60 * 60
        // A change happens at most once within a day either side of the time.
        let before = TimeInterval(timeZone.secondsFromGMT(for: wallClock.addingTimeInterval(-day)))
        let afterChange = TimeInterval(timeZone.secondsFromGMT(for: wallClock.addingTimeInterval(day)))
        // A time that exists with the earlier offset, including the first of a repeated time.
        let withBefore = wallClock.addingTimeInterval(-before)
        if TimeInterval(timeZone.secondsFromGMT(for: withBefore)) == before { return withBefore }
        // A time after the change.
        let withAfter = wallClock.addingTimeInterval(-afterChange)
        if TimeInterval(timeZone.secondsFromGMT(for: withAfter)) == afterChange { return withAfter }
        // A skipped time: the earlier offset puts it the gap's length later on the new clock.
        return withBefore
    }

    /// The hour and minute of an "HH:MM" time on a 24-hour clock, or nil when it is not one.
    static func parse(_ hhmm: String) -> (hour: Int, minute: Int)? {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0 ..< 24).contains(hour), (0 ..< 60).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
