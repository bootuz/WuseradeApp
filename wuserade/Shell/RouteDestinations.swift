// Minimum iOS 17.
//  What each route pushes, in every tab's stack.

import SwiftUI

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .reader(let context):
                ReaderScreen(context: context)
            case .poet(let poet):
                PoetView(poet: poet)
            case .theme(let theme):
                ThemeView(theme: theme)
            }
        }
    }
}
