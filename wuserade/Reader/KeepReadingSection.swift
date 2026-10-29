// Minimum iOS 17.
//  The end of a poem once the server's suggestions arrive: more by the same poet, then poems the reader might
//  also like. Each list opens in the reader as its own list; an empty one is left out.

import SwiftUI

struct KeepReadingSection: View {
    let suggestions: KeepReading
    /// The poet of the poem being read.
    let author: Author

    @Environment(\.navigate) private var navigate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            group(
                label: "\(OwnerCopy.moreBy) \(author.name)",
                poems: suggestions.poetSummaries(author: author),
                subtitle: .none,
                section: "poet"
            )
            group(
                label: OwnerCopy.youMightAlsoLike,
                poems: suggestions.similarSummaries,
                subtitle: .author,
                section: "similar"
            )
        }
    }

    @ViewBuilder
    private func group(label: String, poems: [PoemSummary], subtitle: PoemRowLabel.Subtitle, section: String) -> some View {
        if !poems.isEmpty {
            SectionLabel(text: label)
                .padding(.top, Space.six)
                .padding(.bottom, Space.one)
            ForEach(Array(poems.enumerated()), id: \.element.id) { index, poem in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }
                NextPoemRow(poem: poem, subtitle: subtitle) {
                    AnalyticsManager.shared.keepReadingOpen(section: section)
                    navigate(.reader(ReaderContext(poems: poems, index: index)))
                }
            }
        }
    }
}
