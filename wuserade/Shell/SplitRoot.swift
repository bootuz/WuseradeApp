// Minimum iOS 17.
//  iOS 17 in regular width, where there is no sidebar-adaptable TabView: one NavigationSplitView whose sidebar
//  lists the five tabs (gearshape in its toolbar), the tab's list as the content column, and the reader as the
//  detail.

import SwiftUI

struct SplitRoot: View {
    @Binding var tab: AppTab
    let paths: AppPaths

    @State private var sidebarSelection: AppTab?

    var body: some View {
        @Bindable var paths = paths
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: $sidebarSelection) { item in
                Label(item.title(compact: false), systemImage: item.symbol)
            }
            .navigationTitle("Усэрадэ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
        } content: {
            NavigationStack(path: path(for: tab, in: $paths)) {
                TabColumn(tab: tab, compact: false)
                    .routeDestinations()
            }
            .id(tab)
            .navigationSplitViewColumnWidth(Space.columnContent)
        } detail: {
            SplitDetail(selection: paths.selection(tab), showsDaysPage: tab == .new)
                .id(tab)
        }
        .environment(paths.selection(tab))
        .environment(\.navigate, NavigateAction { [tab] in paths.navigate($0, in: tab, split: true) })
        .onChange(of: tab, initial: true) { _, tab in sidebarSelection = tab }
        .onChange(of: sidebarSelection) { _, selected in
            if let selected { tab = selected }
        }
    }

    private func path(for tab: AppTab, in paths: Bindable<AppPaths>) -> Binding<NavigationPath> {
        switch tab {
        case .new: paths.new
        case .themes: paths.themes
        case .poets: paths.poets
        case .liked: paths.liked
        case .search: paths.search
        }
    }
}
