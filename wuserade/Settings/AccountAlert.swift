// Minimum iOS 17.
//  The words of the alert that follows a failed sign-in, sign-out or account deletion, and which errors get one.
//  The strings are the owner's placeholders from the Firebase work; the ones in brackets are still open.

import Foundation

enum AccountAlert {
    /// The text of the alert for a failed flow, or nil when nothing should be shown (the person closed the sheet).
    static func message(for error: Error) -> String? {
        switch error as? SignInError {
        case .cancelled?: return nil
        case .missingConfiguration?: return configurationMessage
        default: return genericMessage
        }
    }

    // TODO(owner): copy. Meaning: "Signing in isn't available yet."
    static let configurationMessage = String(localized: "Хыхьэныр иджыри хузэфэк\u{04C0}ыркъым.")
    // TODO(owner): copy. Meaning: "Something went wrong. Check your internet connection and try again."
    static let genericMessage = String(localized: "Щыуагъэ къыщыхъуащ. Интернетыр къэпщытэжи аргуэру е\u{04C0}э.")
    // TODO(owner): copy. Meaning: "Error".
    static let title = String(localized: "Щыуагъэ")
    // TODO(owner): copy. Meaning: "OK".
    static let ok = String(localized: "Хъунщ")
}
