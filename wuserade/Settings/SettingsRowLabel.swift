// Minimum iOS 17.
//  A Settings row: the symbol in accent, the title in ink, and arrow.up.forward when the row leaves the app.

import SwiftUI

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var leavesApp = false

    var body: some View {
        HStack {
            Label {
                Text(title).foregroundStyle(Palette.ink)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Palette.accent)
            }
            if leavesApp {
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkTertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}
