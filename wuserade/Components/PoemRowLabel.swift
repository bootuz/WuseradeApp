// Minimum iOS 17.
//  A poem in a list: the title in small caps (or the first line in roman, ending in '…', when untitled),
//  then the poet or the first line in italic. One accessibility element.

import SwiftUI

struct PoemRowLabel: View {
    enum Subtitle { case author, firstLine, none }

    let poem: PoemSummary
    var subtitle: Subtitle = .author
    var highlight = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            if poem.isUntitled {
                HighlightedText(text: poem.firstLine + "…", query: highlight, token: .rowFirstLine)
                    .foregroundStyle(Palette.ink)
            } else {
                HighlightedText(text: poem.title, query: highlight, token: .rowTitle)
                    .foregroundStyle(Palette.ink)
            }
            if let subtitleText {
                HighlightedText(text: subtitleText, query: highlight, token: .rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitleText: String? {
        switch subtitle {
        case .author: poem.author.name
        case .firstLine: poem.isUntitled ? nil : poem.firstLine
        case .none: nil
        }
    }

    private var accessibilityText: String {
        let title = poem.isUntitled ? poem.firstLine + "…" : KabardianText.sentenceCased(poem.title)
        guard let subtitleText else { return title }
        return title + ", " + subtitleText
    }
}
