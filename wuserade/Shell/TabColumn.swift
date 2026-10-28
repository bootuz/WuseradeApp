// Minimum iOS 17.
//  Each tab's list, compact or as a regular-width content column.

import SwiftUI

struct TabColumn: View {
    let tab: AppTab
    let compact: Bool

    var body: some View {
        switch tab {
        case .new:
            if compact { HomeView() } else { NewColumn() }
        case .themes:
            ThemesListView()
        case .poets:
            PoetsView()
        case .liked:
            LikedView()
        case .search:
            SearchView()
        }
    }
}
