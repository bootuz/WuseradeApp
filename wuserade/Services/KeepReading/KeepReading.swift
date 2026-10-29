// Minimum iOS 17.
//  What the reader offers once a poem ends: more poems by the same poet and a couple of similar ones, as the
//  `keepReading` callable returns them, and the small decision of what shows below the closing lozenge.

import Foundation
import OSLog

struct KeepReading: Decodable, Equatable {
    /// A poem by the poet being read. The poet is the reader's own, so the server sends only the poem.
    struct Ref: Decodable, Equatable {
        let id: Int
        let title: String
    }

    /// A poem by any poet, in the same theme or by a poet the reader liked.
    struct Similar: Decodable, Equatable {
        let id: Int
        let title: String
        let authorId: Int
        let authorName: String
    }

    let poet: [Ref]
    let similar: [Similar]

    var isEmpty: Bool { poet.isEmpty && similar.isEmpty }

    /// The poet's rows as list entries, carrying `author`: the poet of the poem being read.
    func poetSummaries(author: Author) -> [PoemSummary] {
        poet.map {
            PoemSummary(id: $0.id, title: $0.title, authorId: author.id, authorName: author.name, themeId: nil, createdAt: .distantPast)
        }
    }

    var similarSummaries: [PoemSummary] {
        similar.map {
            PoemSummary(id: $0.id, title: $0.title, authorId: $0.authorId, authorName: $0.authorName, themeId: nil, createdAt: .distantPast)
        }
    }
}

/// What the end of a poem shows: the suggestions once they arrive, otherwise the list's next poem, if any.
enum KeepReadingState: Equatable {
    case suggestions(KeepReading)
    case next(PoemSummary)
    case nothing

    /// `result` is nil while the suggestions load. An empty or failed result keeps the next row.
    static func resolve(result: Result<KeepReading, Error>?, next: PoemSummary?) -> KeepReadingState {
        if case .success(let suggestions) = result, !suggestions.isEmpty { return .suggestions(suggestions) }
        if let next { return .next(next) }
        return .nothing
    }

    /// Whether a reader page asks for its suggestions now. Only the page being read asks, once the closing
    /// lozenge's top (`endTop`, in the scroll view's space) is less than a screen below the bottom edge, so a
    /// short poem asks at once. Nothing is asked before the page is measured, or when the pager keeps them.
    static func shouldLoad(shown: Bool, endTop: CGFloat, scrollHeight: CGFloat, cached: Bool) -> Bool {
        shown && !cached && scrollHeight > 0 && endTop < scrollHeight * 2
    }

    /// Asks `service` for the suggestions after `poemId`. A failure is logged and otherwise left silent.
    static func load(_ poemId: Int, from service: any KeepReadingService) async -> Result<KeepReading, Error> {
        do {
            return .success(try await service.suggestions(for: poemId))
        } catch {
            logger.debug("No suggestions after poem \(poemId): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "KeepReading"
    )
}
