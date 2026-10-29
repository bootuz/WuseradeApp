import Foundation
import Testing
@testable import Wuserade

/// The same cases as the server's `next_send_at` tests (firebase/functions/tests/test_morning.py): the app and the
/// server must agree on when a device is next due.
struct MorningScheduleTests {
    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    @Test func `nextSendAt matches the server rule`() throws {
        let moscow = try zone("Europe/Moscow")
        // 07:00 in Moscow: today at 08:00. At 08:00 exactly: tomorrow, since the time must be strictly after.
        #expect(MorningSchedule.nextSendAt(timeZone: moscow, notifyAt: "08:00", after: try utc(2026, 10, 29, 4, 0))
            == (try utc(2026, 10, 29, 5, 0)))
        #expect(MorningSchedule.nextSendAt(timeZone: moscow, notifyAt: "08:00", after: try utc(2026, 10, 29, 5, 0))
            == (try utc(2026, 10, 30, 5, 0)))

        let berlin = try zone("Europe/Berlin")
        // A time skipped by the spring change moves forward by the gap: 02:30 becomes 03:30.
        #expect(MorningSchedule.nextSendAt(timeZone: berlin, notifyAt: "02:30", after: try utc(2027, 3, 27, 12, 0))
            == (try utc(2027, 3, 28, 1, 30)))
        // A time repeated by the autumn change uses its first occurrence.
        #expect(MorningSchedule.nextSendAt(timeZone: berlin, notifyAt: "02:30", after: try utc(2026, 10, 24, 12, 0))
            == (try utc(2026, 10, 25, 0, 30)))
    }

    @Test func `nextSendAt in far zones and on the change days`() throws {
        let after = try utc(2026, 10, 29, 12, 0)
        // Kiritimati is UTC+14, Pago Pago UTC-11.
        #expect(MorningSchedule.nextSendAt(timeZone: try zone("Pacific/Kiritimati"), notifyAt: "08:00", after: after)
            == (try utc(2026, 10, 29, 18, 0)))
        #expect(MorningSchedule.nextSendAt(timeZone: try zone("Pacific/Pago_Pago"), notifyAt: "08:00", after: after)
            == (try utc(2026, 10, 29, 19, 0)))
        #expect(MorningSchedule.nextSendAt(timeZone: try zone("Asia/Kolkata"), notifyAt: "08:00", after: try utc(2026, 10, 29, 2, 30))
            == (try utc(2026, 10, 30, 2, 30)))

        // A morning time later on a change day uses that day's new offset.
        let berlin = try zone("Europe/Berlin")
        #expect(MorningSchedule.nextSendAt(timeZone: berlin, notifyAt: "08:00", after: try utc(2027, 3, 27, 12, 0))
            == (try utc(2027, 3, 28, 6, 0)))
        #expect(MorningSchedule.nextSendAt(timeZone: berlin, notifyAt: "08:00", after: try utc(2026, 10, 24, 12, 0))
            == (try utc(2026, 10, 25, 7, 0)))
    }
}
