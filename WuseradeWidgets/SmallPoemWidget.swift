// Minimum iOS 17.
//  The small widget: the short poem of the day, or the day's poem when the reader picks it in the widget's
//  settings. Title, poet and the first 2 lines; a tap opens the poem in the reader.

import SwiftUI
import WidgetKit

struct SmallPoemWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SmallPoemWidget", intent: SmallPoemIntent.self, provider: DailyProvider()) { entry in
            Group {
                if let picks = entry.picks {
                    let poem = entry.smallPoem == .daysPoem ? picks.poem : picks.shortPoem
                    WidgetPoemBlock(poem: poem, date: picks.date, lineCount: 2, titleLines: 2)
                        .widgetURL(DeepLink.poemURL(poem.id, source: "widget"))
                } else {
                    WidgetEmptyState()
                }
            }
            .containerBackground(WidgetPalette.page, for: .widget)
        }
        .configurationDisplayName(WidgetCopy.smallName)
        .description(WidgetCopy.smallDescription)
        .supportedFamilies([.systemSmall])
    }
}
