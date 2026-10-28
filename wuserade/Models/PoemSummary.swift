import Foundation

/// One catalog entry: everything a list row needs without loading the poem body.
/// Mirrors an element of `catalog/{n}.entries` as written by the admin tool.
struct PoemSummary: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let authorId: Int
    let authorName: String
    let themeId: Int?
    let createdAt: Date

    var author: Author { Author(id: authorId, name: authorName) }
}
