import Foundation

/// An author row in `meta/content.authors`, with its poem count.
struct AuthorEntry: Codable, Hashable {
    let id: Int
    let name: String
    let poemsCount: Int

    var author: Author { Author(id: id, name: name) }
}

/// The `meta/content` Firestore document: catalog version info plus the author and theme lists.
struct ContentMeta: Codable, Equatable {
    let catalogVersion: Int
    let catalogChunks: Int
    let authors: [AuthorEntry]
    let themes: [Category]
    let nextPoemId: Int
    let minimumAppVersion: String?
}
