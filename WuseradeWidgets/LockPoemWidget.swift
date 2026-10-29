// Minimum iOS 17.
//  The lock-screen widget: '<title> · <poet>' over the first line of the day's poem, in the system font the lock
//  screen tints. With nothing to show it carries the lozenge and the app's name. A tap opens the poem.

import SwiftUI
import WidgetKit

struct LockPoemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockPoemWidget", provider: DailyProvider()) { entry in
            Group {
                if let poem = entry.picks?.poem {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Self.heading(poem))
                            .font(.headline)
                            .lineLimit(1)
                            .widgetAccentable()
                        Text(DailyTimeline.openingLines(of: poem.text, limit: 1).first?.kbd ?? "")
                            .font(.body)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .widgetURL(DeepLink.poemURL(poem.id, source: "widget"))
                } else {
                    HStack(spacing: Space.two) {
                        LozengeShape()
                            .frame(width: 6, height: 9)
                            .accessibilityHidden(true)
                        Text(WidgetCopy.appName)
                            .font(.headline)
                    }
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .containerBackground(for: .widget) {}
        }
        .configurationDisplayName(WidgetCopy.lockName)
        .description(WidgetCopy.lockDescription)
        .supportedFamilies([.accessoryRectangular])
    }

    /// The title in sentence case, since the system font has no small caps, then the poet. An untitled poem
    /// shows the poet alone; its first line follows anyway.
    private static func heading(_ poem: DailyPoem) -> String {
        let title = KabardianText.title(poem.title)
        let poet = poem.authorName.kbd
        return title.isEmpty ? poet : "\(KabardianText.sentenceCased(title)) · \(poet)"
    }
}
