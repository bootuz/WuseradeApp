// Minimum iOS 17.
//  One navigation path and one detail selection per tab, owned by the root so both survive a size-class
//  change: an iPad window crossing compact width, or an iPhone Duo folding or unfolding.

import SwiftUI

@Observable
final class AppPaths {
    var new = NavigationPath()
    var themes = NavigationPath()
    var poets = NavigationPath()
    var liked = NavigationPath()
    var search = NavigationPath()

    @ObservationIgnored private let selections = Dictionary(
        uniqueKeysWithValues: AppTab.allCases.map { ($0, SplitSelection()) }
    )

    func selection(_ tab: AppTab) -> SplitSelection {
        selections[tab] ?? SplitSelection()
    }

    func append(_ route: Route, in tab: AppTab) {
        switch tab {
        case .new: new.append(route)
        case .themes: themes.append(route)
        case .poets: poets.append(route)
        case .liked: liked.append(route)
        case .search: search.append(route)
        }
    }

    /// Compact stacks push every route. The split selects a poem into the detail, and pushes poets and themes
    /// inside the content column.
    func navigate(_ route: Route, in tab: AppTab, split: Bool) {
        if split, case .reader(let context) = route {
            let selection = selection(tab)
            selection.context = context.poems
            selection.poemID = context.current?.id
        } else {
            append(route, in: tab)
        }
    }
}
