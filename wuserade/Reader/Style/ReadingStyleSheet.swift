// Minimum iOS 17.
//  Теплъэр from the reader's Aa button: a 320-wide popover in regular width, and in compact width a sheet at
//  the medium detent (large at accessibility sizes) that leaves the poem behind it live.

import SwiftUI

struct ReadingStyleSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ReadingStyleForm()
                .navigationTitle("Теплъэр")
                .navigationBarTitleDisplayMode(.inline)
        }
        .frame(idealWidth: 320, idealHeight: 420)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationBackground(Palette.pageElevated)
        .presentationCompactAdaptation(.sheet)
    }
}
