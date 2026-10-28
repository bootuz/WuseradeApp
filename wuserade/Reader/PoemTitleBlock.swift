// Minimum iOS 17.
//  The title (a header, read in sentence case) and the poet as its own accent link with a chevron.
//  An untitled poem is headed by the asterism, labelled with its first line.

import SwiftUI

struct PoemTitleBlock: View {
    let poem: PoemSummary
    /// dayTitle on the day's page and in the regular-width reader; poemTitle otherwise.
    var large = false
    /// The day's page opens the reader from its title.
    var onTitle: (() -> Void)?
    var onAuthor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.one) {
            if let onTitle {
                Button(action: onTitle) { title }
                    .buttonStyle(.plain)
            } else {
                title
            }
            Button(action: onAuthor) {
                HStack(alignment: .firstTextBaseline, spacing: Space.one) {
                    Text(poem.author.name)
                        .serif(.authorLine)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Palette.accent)
                // A 44pt hit area without changing the line's own height.
                .padding(.vertical, 10)
                .contentShape(.rect)
                .padding(.vertical, -10)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var title: some View {
        if poem.isUntitled {
            Lozenge(kind: .asterism, headerLabel: poem.firstLine + "…")
                .padding(.bottom, Space.two)
        } else {
            Text(poem.title)
                .serif(large ? .dayTitle : .poemTitle)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(KabardianText.sentenceCased(poem.title))
                .accessibilityAddTraits(.isHeader)
        }
    }
}
