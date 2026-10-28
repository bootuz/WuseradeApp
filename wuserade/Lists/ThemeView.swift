// Minimum iOS 17.
//  One theme's poems, each row showing its poet.

import FirebaseAnalytics
import SwiftUI

struct ThemeView: View {
    let theme: Category

    @Environment(Catalog.self) private var catalog

    var body: some View {
        PoemCollectionView(name: theme.title, subtitle: .author, emptyTitle: OwnerCopy.emptyTheme) {
            try await catalog.poems(ofTheme: theme.id)
        }
        .analyticsScreen(name: "PoemCategoryView", extraParameters: ["category": theme.title])
    }
}
