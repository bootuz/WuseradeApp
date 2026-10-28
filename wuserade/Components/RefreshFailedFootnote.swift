// Minimum iOS 17.
//  The last row of a list whose refresh failed: everything stays on screen and this line says so.

import SwiftUI

struct RefreshFailedFootnote: View {
    var body: some View {
        Text(OwnerCopy.refreshFailed)
            .font(.footnote)
            .foregroundStyle(Palette.inkTertiary)
            .contentRow(separator: .hidden)
    }
}
