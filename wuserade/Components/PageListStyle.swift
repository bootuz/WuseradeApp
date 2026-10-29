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
    /// A `centred` row gets the leading inset on both sides, so what it centres sits in the middle of the list;
    /// the usual trailing inset is narrower, which suits left-aligned text but puts a centred element off-centre.
    func contentRow(separator: Visibility = .automatic, selectable: Bool = false, centred: Bool = false) -> some View {
        modifier(ContentRowModifier(separator: separator, selectable: selectable, centred: centred))
    }
}

private struct ContentRowModifier: ViewModifier {
    var separator: Visibility
    var selectable: Bool
    var centred: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let leading = dynamicTypeSize.isAccessibilitySize ? Space.readingMarginAX : Space.readingMargin
        content
            .listRowInsets(EdgeInsets(
                top: Space.three,
                leading: leading,
                bottom: Space.three,
                trailing: centred ? leading : Space.four
            ))
            .listRowBackground(selectable ? nil : Palette.page)
            .listRowSeparatorTint(Palette.hairline)
            .listRowSeparator(separator)
    }
}
