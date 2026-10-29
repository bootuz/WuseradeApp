// Minimum iOS 17.
//  What is known about the photo a reader sent for a poet.

import Foundation

enum WaitingStatus: Equatable {
    /// Not asked yet, or forgotten when the account changed.
    case unchecked
    /// A photo from this reader is waiting for the owner.
    case waiting
    case notWaiting
    /// The record could not be read, e.g. offline.
    case failed
}
