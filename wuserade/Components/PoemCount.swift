// Minimum iOS 17.
//  A poet's or theme's number of poems: the number, then the poems tab's symbol in place of a noun.
//  VoiceOver still reads the number with the noun.

import SwiftUI

struct PoemCount: View {
    let count: Int
    let token: TypeToken

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.one) {
            Text(verbatim: "\(count)")
            Image(systemName: AppTab.new.symbol)
                .imageScale(.small)
        }
        .serif(token)
        .foregroundStyle(Palette.inkSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(count))
    }

    static func spoken(_ count: Int) -> String {
        "\(count) \(OwnerCopy.countNoun)"
    }
}
