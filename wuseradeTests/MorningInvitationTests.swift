// Minimum iOS 17.
//  The one-time invitation to the morning poem: the reader's distinct days, and when Home shows it.

import Foundation
import Testing
@testable import Wuserade

final class MorningInvitationTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own defaults suite.
    private let suiteName = "MorningInvitationTests-\(UUID().uuidString)"
    private let zone = TimeZone(identifier: "Europe/Moscow")!

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    /// Hour `hour` on 2026-10-`day`, in Moscow.
    private func at(day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func shows(_ days: VisitDays, enabled: Bool = false) -> Bool {
        MorningInvitation.shouldShow(visitDays: days.count, done: days.invitationDone, enabled: enabled)
    }

    @Test func `Invitation shows on the third day only until answered`() throws {
        var days = VisitDays(defaults: try defaults())
        #expect(days.count == 0)
        #expect(!shows(days))

        days.record(at(day: 27, 9), in: zone)
        #expect(!shows(days), "first day")
        days.record(at(day: 28, 9), in: zone)
        #expect(!shows(days), "second day")
        days.record(at(day: 29, 9), in: zone)
        #expect(days.count == 3)
        #expect(shows(days), "third day")
        #expect(!shows(days, enabled: true), "never once the morning poem is on")

        // A fresh read of the same defaults sees the same days.
        var reread = VisitDays(defaults: try defaults())
        #expect(reread.count == 3)
        #expect(shows(reread))

        reread.invitationDone = true
        #expect(!shows(reread), "answered")
        var later = VisitDays(defaults: try defaults())
        #expect(later.invitationDone, "the answer is kept")
        later.record(at(day: 30, 9), in: zone)
        later.record(at(day: 31, 9), in: zone)
        #expect(!shows(later), "never again after either choice")
    }

    @Test func `Same day twice is one visit`() throws {
        var days = VisitDays(defaults: try defaults())
        days.record(at(day: 29, 0), in: zone)
        days.record(at(day: 29, 23), in: zone)
        #expect(days.count == 1)

        // Midnight in the reader's time zone starts a new day.
        days.record(at(day: 30, 0), in: zone)
        #expect(days.count == 2)
    }

    @Test func `Keeps at most three days`() throws {
        var days = VisitDays(defaults: try defaults())
        for day in 20...29 { days.record(at(day: day, 12), in: zone) }
        #expect(days.count == 3)
    }

    @Test func `Only the third day, unanswered and off, shows it`() {
        #expect(!MorningInvitation.shouldShow(visitDays: 2, done: false, enabled: false))
        #expect(MorningInvitation.shouldShow(visitDays: 3, done: false, enabled: false))
        #expect(!MorningInvitation.shouldShow(visitDays: 3, done: true, enabled: false))
        #expect(!MorningInvitation.shouldShow(visitDays: 3, done: false, enabled: true))
    }
}
