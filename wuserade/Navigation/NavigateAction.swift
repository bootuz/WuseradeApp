// Minimum iOS 17.
//  Opens a route from anywhere inside a tab: compact stacks push it, and the regular-width split selects a poem
//  into the detail or pushes a poet or theme inside the content column.

import SwiftUI

struct NavigateAction {
    var handler: (Route) -> Void = { _ in }

    func callAsFunction(_ route: Route) {
        handler(route)
    }
}

extension EnvironmentValues {
    @Entry var navigate = NavigateAction()
}
