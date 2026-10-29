// Minimum iOS 17.
//  What a home-screen widget shows with no daily document, neither read nor cached: the lozenge and the app's
//  name, never a placeholder poem. A tap opens the app.

import SwiftUI

struct WidgetEmptyState: View {
    var body: some View {
        VStack(spacing: Space.two) {
            LozengeShape()
                .fill(WidgetPalette.gilt)
                .frame(width: 12, height: 18)
            Text(WidgetCopy.appName)
                .serif(.widgetWordmark)
                .foregroundStyle(WidgetPalette.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
