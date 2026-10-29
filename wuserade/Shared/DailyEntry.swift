// Minimum iOS 17.
//  One moment of the widgets' timeline: the day's picks to show, or none for the empty state and for the
//  midnight entry that makes the widget read the new day.

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
