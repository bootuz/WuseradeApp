// Minimum iOS 17.
//  One catalog entry: everything a list row and the reader's context need without loading the poem body.
//  Mirrors an element of `catalog/{n}.entries` as written by the admin tool. The title and the poet's name are
//  normalised for display when the entry is made, so every screen shows the palochka as Ӏ.

import Foundation

struct PoemSummary: Codable, Identifiable, Hashable {
    let id: Int
    /// Empty for an untitled poem, which lists by its first line.
    let title: String
    let authorId: Int
    let authorName: String
    let themeId: Int?
    let createdAt: Date
    /// The first verse line, known only when the poem's text has been loaded. Catalog entries carry no text,
    /// so it is empty for them.
    let firstLine: String

    var author: Author { Author(id: authorId, name: authorName) }
    var isUntitled: Bool { title.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, title, authorId, authorName, themeId, createdAt
    }

    init(id: Int, title: String, authorId: Int, authorName: String, themeId: Int?, createdAt: Date, firstLine: String = "") {
        self.id = id
        self.title = KabardianText.title(title)
        self.authorId = authorId
        self.authorName = authorName.kbd
        self.themeId = themeId
        self.createdAt = createdAt
        self.firstLine = firstLine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            authorId: try container.decode(Int.self, forKey: .authorId),
            authorName: try container.decode(String.self, forKey: .authorName),
            themeId: try container.decodeIfPresent(Int.self, forKey: .themeId),
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }

    /// A poem opened outside the catalog (the day's poem, a like). It has no theme or date of its own.
    init(_ poem: Poem) {
        self.init(
            id: poem.id,
            title: poem.title,
            authorId: poem.author.id,
            authorName: poem.author.name,
            themeId: nil,
            createdAt: .distantPast,
            firstLine: Self.firstLine(of: poem.content)
        )
    }

    init(_ like: Like) {
        self.init(
            id: like.poemId,
            title: like.title,
            authorId: like.authorId,
            authorName: like.authorName,
            themeId: nil,
            createdAt: like.likedAt,
            firstLine: Self.firstLine(of: like.text)
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
