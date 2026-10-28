// Minimum iOS 17.
//  Where the day's poem comes from. The app uses `DailyRotation`; `NoDaysPoem` leaves the day's page out
//  entirely, for previews or if the rotation is ever switched off.

import Foundation

protocol DaysPoemSource {
    func poem(for date: Date) async -> Poem?
}

struct NoDaysPoem: DaysPoemSource {
    func poem(for date: Date) async -> Poem? { nil }
}
