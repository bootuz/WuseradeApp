// Minimum iOS 17.
//  One theme's poems, each row showing its poet.

import FirebaseAnalytics
import SwiftUI

struct ThemeView: View {
    let theme: Category

    @Environment(Library.self) private var library

    var body: some View {
        PoemCollectionView(name: theme.title, subtitle: .author, emptyTitle: OwnerCopy.emptyTheme,
                           poems: library.poems(ofTheme: theme.id))
        .analyticsScreen(name: "PoemCategoryView", extraParameters: ["category": theme.title])
    }
}
