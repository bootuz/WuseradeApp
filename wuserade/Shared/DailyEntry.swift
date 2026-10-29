// Minimum iOS 17.
//  One moment of the widgets' timeline: the day's picks to show, or none (neither read nor cached) for the
//  empty state.

import Foundation
import WidgetKit

struct DailyEntry: TimelineEntry {
    let date: Date
    let picks: DailyPicks?
    /// Which poem the small widget shows, from its configuration. The other widgets ignore it.
    var smallPoem: SmallPoem = .shortPoem

    enum SmallPoem: Hashable {
        case shortPoem, daysPoem
    }
}
