// Minimum iOS 17.
//  A form sheet on iPad from iOS 18; the default sheet before it.

import SwiftUI

struct FormSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.presentationSizing(.form)
        } else {
            content
        }
    }
}
