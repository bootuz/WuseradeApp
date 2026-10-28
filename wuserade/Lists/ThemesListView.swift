// Minimum iOS 17.
//  Зытеухуар as its own tab, in regular width only (compact Home shows the themes as a section).
//  The API gives no poem counts, so the rows show none.

import SwiftUI

struct ThemesListView: View {
    @Environment(Catalog.self) private var catalog

    var body: some View {
        Group {
            if let themes = catalog.themes {
                List(themes) { theme in
                    NavigationLink(value: Route.theme(theme)) {
                        NameRowLabel(name: theme.title)
                    }
                    .contentRow()
                }
                .pageList()
                .refreshable { await catalog.refreshHome() }
            } else if catalog.homeFailed {
                ScrollView {
                    OfflineStateView { await catalog.refreshHome() }
                }
            } else {
                LoadingPlaceholder(kind: .nameRows)
                    .padding(.horizontal, Space.readingMargin)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.page)
        .navigationTitle("Зытеухуар")
        .task { await catalog.loadHome() }
    }
}
