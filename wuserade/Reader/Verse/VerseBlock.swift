// Minimum iOS 17.
//  A run of lines between section breaks. '***' and '* * *' become the gilt asterism.

import Foundation

enum VerseBlock: Hashable {
    case lines([VerseLine])
    case asterism
}
