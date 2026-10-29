// Minimum iOS 17.
//  The day's short poem on Home: a label, the title block and the whole poem, so there is something to read
//  without a tap. Emits list rows, so it sits inside Home's List.

import SwiftUI

struct ShortPoemSection: View {
    let poem: DailyPoem

    @Environment(\.navigate) private var navigate

    var body: some View {
        let summary = poem.summary

        SectionLabel(text: OwnerCopy.shortPoem)
            .padding(.top, Space.six)
            .contentRow(separator: .hidden)

        VStack(alignment: .leading, spacing: 0) {
            PoemTitleBlock(poem: summary, onTitle: {
                AnalyticsManager.shared.dailyOpen(source: "home_short")
                navigate(.reader(ReaderContext(single: summary)))
            }, onAuthor: {
                AnalyticsManager.shared.dailyOpen(source: "home_short")
                navigate(.poet(summary.author))
            })
            VerseView(poem: ParsedPoem(poem.text))
                .padding(.top, Space.four)
        }
        .contentRow(separator: .hidden)
    }
}
