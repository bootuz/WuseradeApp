// Minimum iOS 17.
//  What sits under a poet's count line: the button that sends a photo, the line saying one is waiting for review,
//  or nothing.

import Foundation

enum SendAreaState: Equatable {
    case button, waiting, hidden

    /// A poet with a photo has nothing to send. A reader who is signed in waits for the check of the waiting
    /// record before seeing anything, so the button never shows and then turns into the waiting line. A failed
    /// check shows nothing too: the button would invite a second photo for a poet that may already have one.
    static func resolve(hasPhoto: Bool, isSignedIn: Bool, waiting: WaitingStatus) -> SendAreaState {
        if hasPhoto { return .hidden }
        guard isSignedIn else { return .button }
        switch waiting {
        case .notWaiting: return .button
        case .waiting: return .waiting
        case .failed, .unchecked: return .hidden
        }
    }
}
