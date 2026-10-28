// Minimum iOS 17.
//  One poet's poems in the Kabardian sort, each row showing its first line (the poet is already known).

import FirebaseAnalytics
import SwiftUI

struct PoetView: View {
    let poet: Author

    @Environment(Library.self) private var library

    var body: some View {
        PoemCollectionView(name: poet.name, subtitle: .firstLine, emptyTitle: OwnerCopy.emptyPoet,
                           poems: library.poems(ofPoet: poet.id))
        .analyticsScreen(name: "AuthorView", extraParameters: ["author": poet.name])
    }
}
