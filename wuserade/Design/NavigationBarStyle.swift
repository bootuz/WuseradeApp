// Minimum iOS 17.
//  Large titles on tab roots are set in Alegreya Medium. Only largeTitleTextAttributes change, so the
//  collapsed bar keeps its system background on iOS 17 and 18 and Liquid Glass on iOS 26.
//  Proxy changes reach only bars created afterwards; after a text-size or Bold Text change, the new
//  face shows when each bar is next created.

import UIKit

enum NavigationBarStyle {
    static func apply() {
        let cut = UIAccessibility.isBoldTextEnabled ? SerifFace.Cut.bold : SerifFace.Cut.medium
        guard let base = UIFont(name: cut.rawValue, size: 34) else { return }
        let font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: base)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIPalette.ink]

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = attributes

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = attributes

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = standard
        proxy.compactAppearance = standard
        proxy.scrollEdgeAppearance = scrollEdge
    }
}
