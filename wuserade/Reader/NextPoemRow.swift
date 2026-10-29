// Minimum iOS 17.
//  The last row of the reader: the next poem in the list it was opened from, or a suggestion to keep reading.

import SwiftUI

struct NextPoemRow: View {
    let poem: PoemSummary
    var subtitle: PoemRowLabel.Subtitle = .author
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.three) {
                PoemRowLabel(poem: poem, subtitle: subtitle)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Space.three)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
