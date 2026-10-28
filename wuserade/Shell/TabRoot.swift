// Minimum iOS 17.
//  One tab's content. Compact width: a NavigationStack with the gearshape on its root. Regular width: a
//  two-column NavigationSplitView, the tab's list as a 320-wide content column (with its own stack for poets and
//  themes) and the reader as the detail. Never a nested three-column split.

import SwiftUI

struct TabRoot<Column: View>: View {
    let tab: AppTab
    let paths: AppPaths
    @ViewBuilder var column: (_ compact: Bool) -> Column

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var paths = paths
        if sizeClass == .compact {
            NavigationStack(path: path(in: $paths)) {
                column(true)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
                    }
                    .routeDestinations()
            }
            .environment(\.navigate, NavigateAction { paths.navigate($0, in: tab, split: false) })
        } else {
            NavigationSplitView {
                NavigationStack(path: path(in: $paths)) {
                    column(false)
                        .routeDestinations()
                }
                .navigationSplitViewColumnWidth(Space.columnContent)
            } detail: {
                SplitDetail(selection: paths.selection(tab), showsDaysPage: tab == .new)
            }
            .environment(paths.selection(tab))
            .environment(\.navigate, NavigateAction { paths.navigate($0, in: tab, split: true) })
        }
    }

    private func path(in paths: Bindable<AppPaths>) -> Binding<NavigationPath> {
        switch tab {
        case .new: paths.new
        case .themes: paths.themes
        case .poets: paths.poets
        case .liked: paths.liked
        case .search: paths.search
        }
    }
}
