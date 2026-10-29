// Minimum iOS 17.
//  A poem as the home-screen widgets show it: the head (gilt lozenge, an optional label, the document's day),
//  the title in small caps or the asterism for an untitled poem, the poet, and the opening lines.

import SwiftUI

struct WidgetPoemBlock: View {
    let poem: DailyPoem
    /// The daily document's own date, `yyyy-MM-dd`: an older cached day shows its own date.
    let date: String
    var label: String?
    var lineCount: Int
    var titleLines = 1

    var body: some View {
        let title = KabardianText.title(poem.title)
        let lines = DailyTimeline.openingLines(of: poem.text, limit: lineCount).map(\.kbd)

        VStack(alignment: .leading, spacing: 0) {
            head

            Group {
                if title.isEmpty {
                    LozengeShape(asterism: true)
                        .fill(WidgetPalette.gilt)
                        .frame(width: 11, height: 13)
                        .padding(.vertical, Space.one)
                } else {
                    Text(title)
                        .serif(.widgetTitle)
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(titleLines)
                }
            }
            .padding(.top, Space.two)

            Text(poem.authorName.kbd)
                .serif(.widgetAuthor)
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
                .padding(.top, Space.half)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index])
                        .serif(.widgetVerse)
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(1)
                }
            }
            .padding(.top, Space.two)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(title: title, lines: lines))
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.two) {
            LozengeShape()
                .fill(WidgetPalette.gilt)
                .frame(width: 6, height: 9)
            if let label {
                Text(label)
                    .serif(.widgetLabel)
                    .foregroundStyle(WidgetPalette.gilt)
                    .lineLimit(1)
                Spacer(minLength: Space.two)
            }
            if let day = DailyTimeline.dayAndMonth(of: date) {
                Text(verbatim: day)
                    .serif(.widgetFolio)
                    .foregroundStyle(WidgetPalette.inkSecondary)
            }
        }
    }

    private func accessibilityText(title: String, lines: [String]) -> String {
        let heading = title.isEmpty ? [] : [KabardianText.sentenceCased(title)]
        return (heading + [poem.authorName.kbd] + lines).joined(separator: ", ")
    }
}
