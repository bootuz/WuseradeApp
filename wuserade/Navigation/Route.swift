// Minimum iOS 17.
//  Everything a tab's navigation stack can push.

import Foundation

enum Route: Hashable {
    case reader(ReaderContext)
    case poet(Author)
    case theme(Category)
}
