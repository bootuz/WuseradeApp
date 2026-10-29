// Minimum iOS 17.
//  One poet's poems in the Kabardian sort, each row showing its first line (the poet is already known).
//  The page opens with the poet's round portrait; the placeholder author of anonymous poems keeps the plain header.

import FirebaseAnalytics
import SwiftUI

struct PoetView: View {
    let poet: Author

    @Environment(Library.self) private var library

    var body: some View {
        let poems = library.poems(ofPoet: poet.id)
        Group {
            if poet.isUnknownAuthor {
                PoemCollectionView(name: poet.name, subtitle: .firstLine, emptyTitle: OwnerCopy.emptyPoet,
                                   poems: poems)
            } else {
                PoemCollectionView(name: poet.name, subtitle: .firstLine, emptyTitle: OwnerCopy.emptyPoet,
                                   poems: poems, headerIsCentred: true) {
                    PoetHeader(poet: poet, count: $0)
                }
            }
        }
        .analyticsScreen(name: "AuthorView", extraParameters: ["author": poet.name])
    }
}
