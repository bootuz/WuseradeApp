// Minimum iOS 17.
//  The medium widget: the day's poem under the day's-page head, with up to 4 lines of its first stanza. A tap
//  opens the poem in the reader.

import SwiftUI
import WidgetKit

struct DaysPoemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaysPoemWidget", provider: DailyProvider()) { entry in
            Group {
                if let picks = entry.picks {
                    WidgetPoemBlock(poem: picks.poem, date: picks.date, label: WidgetCopy.daysPageLabel, lineCount: 4)
                        .widgetURL(DeepLink.poemURL(picks.poem.id, source: "widget"))
                } else {
                    WidgetEmptyState()
                }
            }
            .containerBackground(WidgetPalette.page, for: .widget)
        }
        .configurationDisplayName(WidgetCopy.daysPoemName)
        .description(WidgetCopy.daysPoemDescription)
        .supportedFamilies([.systemMedium])
    }
}
