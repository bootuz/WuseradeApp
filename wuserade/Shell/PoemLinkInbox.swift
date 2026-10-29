// Minimum iOS 17.
//  Holds the poem link that a URL or a tapped morning notification delivered until `RootView` opens it. A tap that
//  launches the app arrives before `RootView` exists; the link waits here, and `RootView` opens it when it appears.

import Foundation
import Observation

@Observable
final class PoemLinkInbox {
    /// The link waiting to be opened. Only the latest is kept.
    private(set) var pending: URL?

    func deliver(_ url: URL) {
        pending = url
    }

    /// The waiting link, which is then no longer pending.
    func take() -> URL? {
        defer { pending = nil }
        return pending
    }
}
