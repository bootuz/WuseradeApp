// Minimum iOS 17.
//  How far a scroll view's content has moved under its top bar, from iOS 18. iOS 17 has no scroll geometry,
//  so the reader measures its content's frame instead and this does nothing.

import SwiftUI

struct ScrollDistanceReader: ViewModifier {
    @Binding var distance: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in
                distance = value
            }
        } else {
            content
        }
    }
}
