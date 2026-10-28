// Minimum iOS 17.
//  Where the day's poem comes from. The app uses `DailyRotation`; `NoDaysPoem` leaves the day's page out
//  entirely, for previews or if the rotation is ever switched off.

import Foundation

protocol DaysPoemSource {
    /// Picks from `entries`, the whole catalog.
    func poem(for date: Date, in entries: [PoemSummary]) async -> Poem?
}

struct NoDaysPoem: DaysPoemSource {
    func poem(for date: Date, in entries: [PoemSummary]) async -> Poem? { nil }
}
