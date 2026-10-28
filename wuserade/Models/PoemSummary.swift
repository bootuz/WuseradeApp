// Minimum iOS 17.
//  What a list row and the reader's context need to know about a poem, with the text already normalised.

import Foundation

struct PoemSummary: Hashable, Identifiable {
    let id: Int
    /// Empty for an untitled poem, which lists by its first line.
    let title: String
    let author: Author
    let firstLine: String

    var isUntitled: Bool { title.isEmpty }

    init(id: Int, title: String, author: Author, firstLine: String) {
        self.id = id
        self.title = KabardianText.title(title)
        self.author = Author(id: author.id, name: author.name.kbd)
        self.firstLine = firstLine
    }

    init(_ poem: Poem) {
        self.init(
            id: poem.id,
            title: poem.title,
            author: poem.author,
            firstLine: Self.firstLine(of: poem.content)
        )
    }

    init(_ persisted: PersistedPoem) {
        self.init(
            id: persisted.poemID,
            title: persisted.title,
            author: Author(
                id: persisted.author.authorID,
                name: persisted.author.name
            ),
            firstLine: Self.firstLine(of: persisted.text)
        )
    }

    /// The first verse line, without trailing punctuation, for untitled rows and a poet's list.
    static func firstLine(of text: String) -> String {
        let line = text.kbd
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?—– "))
    }
}
