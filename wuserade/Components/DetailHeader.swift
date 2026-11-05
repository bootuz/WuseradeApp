// Minimum iOS 17.
//  The full poet or theme name as the first item of its list, with an optional count line.

import SwiftUI

struct DetailHeader: View {
    let name: String
    var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.two) {
            Text(name)
                .serif(.headerTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let count {
                PoemCount(count: count, token: .sectionLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.two)
        .padding(.bottom, Space.three)
    }
}
