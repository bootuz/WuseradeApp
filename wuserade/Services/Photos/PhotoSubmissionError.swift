// Minimum iOS 17.
//  Why a photo could not be sent, when the reader (not the network) is the reason.

import Foundation

enum PhotoSubmissionError: Error, Equatable {
    /// The server refused the upload: the account is blocked from sending photos.
    case banned
    /// Photos can only be sent from an Apple or Google account.
    case notSignedIn
}
