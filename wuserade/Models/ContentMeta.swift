import Foundation

/// An author row in `meta/content.authors`, with its poem count.
struct AuthorEntry: Codable, Hashable {
    let id: Int
    let name: String
    let poemsCount: Int

    var author: Author { Author(id: id, name: name) }
}

/// The `meta/content` Firestore document: catalog version info plus the author and theme lists.
/// `minimumAppVersion` is read separately, through `MetaDocument`.
struct ContentMeta: Codable, Equatable {
    let catalogVersion: Int
    let catalogChunks: Int
    let authors: [AuthorEntry]
    let themes: [Category]
    let nextPoemId: Int
}

/// One read of `meta/content`.
struct MetaDocument {
    /// `minimumAppVersion`, read on its own: nil when it is missing, null or not a string. Reading it apart
    /// from the rest means a build still learns it must be updated when a newer `meta/content` has a shape
    /// it cannot decode.
    let minimumAppVersion: String?
    /// The rest of the document, or the error from decoding it.
    let meta: Result<ContentMeta, Error>
}
