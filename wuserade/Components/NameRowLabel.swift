// Minimum iOS 17.
//  A poet or theme name with an optional trailing poem count. The count stacks under the name at
//  accessibility text sizes. Names are never small caps.

import SwiftUI

struct NameRowLabel: View {
    let name: String
    var count: Int?
    var italic = false
    var highlight = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.half))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.three))
        layout {
            HighlightedText(text: name, query: highlight, token: italic ? .rowSubtitle : .rowName)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text(count, format: .number)
                    .serif(.rowMeta)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
