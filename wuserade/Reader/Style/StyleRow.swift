// Minimum iOS 17.
//  One row of the reading-style form: the label leading and its control trailing, or the label above the
//  control at accessibility text sizes.

import SwiftUI

struct StyleRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.two))
            : AnyLayout(HStackLayout(spacing: Space.four))
        layout {
            Text(label)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            control
        }
        .listRowBackground(Palette.cellElevated)
    }
}
