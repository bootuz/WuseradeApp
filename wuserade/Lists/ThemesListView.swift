// Minimum iOS 17.
//  Зытеухуар as its own tab, in regular width only (compact Home shows the themes as a section).
//  The API gives no poem counts, so the rows show none.

import SwiftUI

struct ThemesListView: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if let themes = library.themes {
                List(themes) { theme in
                    NavigationLink(value: Route.theme(theme)) {
                        NameRowLabel(name: theme.title)
                    }
                    .contentRow()
                }
                .pageList()
                .refreshable { await library.refreshHome() }
            } else if library.homeFailed {
                ScrollView {
                    OfflineStateView { await library.refreshHome() }
                }
            } else {
                LoadingPlaceholder(kind: .nameRows)
                    .padding(.horizontal, Space.readingMargin)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.page)
        .navigationTitle("Зытеухуар")
        .task { await library.loadHome() }
    }
}
