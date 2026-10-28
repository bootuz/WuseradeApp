// Minimum iOS 17.
//  Content lists sit on page with hairline separators. Poem, poet and theme rows never sit on cells.

import SwiftUI

extension View {
    /// A plain list on the page colour, with section headers in sentence case.
    func pageList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .textCase(nil)
    }

    /// A content row: page ground, hairline separator, inset to the reading margin. Rows in a
    /// `List(selection:)` pass `selectable` so the system can draw the selection; a row background hides it.
    func contentRow(separator: Visibility = .automatic, selectable: Bool = false) -> some View {
        modifier(ContentRowModifier(separator: separator, selectable: selectable))
    }
}

private struct ContentRowModifier: ViewModifier {
    var separator: Visibility
    var selectable: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(
                top: Space.three,
                leading: dynamicTypeSize.isAccessibilitySize ? Space.readingMarginAX : Space.readingMargin,
                bottom: Space.three,
                trailing: Space.four
            ))
            .listRowBackground(selectable ? nil : Palette.page)
            .listRowSeparatorTint(Palette.hairline)
            .listRowSeparator(separator)
    }
}
