// Minimum iOS 17.
//  Opens the poem a link or a tapped notification names. A poem that cannot be fetched (missing, or offline)
//  opens nothing and shows no error.

import Foundation
import os

enum PoemLinkOpener {
    static func open(id: Int, fetch: (Int) async throws -> Poem, navigate: (Poem) -> Void) async {
        do {
            navigate(try await fetch(id))
        } catch {
            logger.debug("Poem link \(id, privacy: .public) opens nothing: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "PoemLinkOpener"
    )
}
