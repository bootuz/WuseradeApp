// Minimum iOS 17.
//  Minimises the tab bar on scroll from iOS 26; earlier versions keep it.

import SwiftUI

struct MinimizesTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
