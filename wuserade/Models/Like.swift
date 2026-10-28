import Foundation

/// A liked poem, stored at `users/{uid}/likes/{poemId}`. It carries a snapshot of the poem
/// so the Liked tab and the poem screen work offline without reading `poems/{id}`.
///
/// The stored fields are exactly the six the security rules allow. `id` is computed, so it is
/// not encoded.
struct Like: Codable, Identifiable, Hashable {
    let poemId: Int
    let likedAt: Date
    let title: String
    let authorId: Int
    let authorName: String
    let text: String

    var id: Int { poemId }

    /// The poem as it was when it was liked.
    var poem: Poem {
        Poem(id: poemId, title: title, author: Author(id: authorId, name: authorName), content: text)
    }
}

extension Like {
    // In an extension, so the memberwise initializer stays available.
    init(poem: Poem, likedAt: Date = .now) {
        self.init(
            poemId: poem.id,
            likedAt: likedAt,
            title: poem.title,
            authorId: poem.author.id,
            authorName: poem.author.name,
            text: poem.content
        )
    }
}
