// Minimum iOS 17.
//  The day's picks from `daily/{YYYY-MM-DD}`: the day's poem, a short poem and the poet of the day. Written by
//  the server a week ahead in the reader's local date; read by Home and the widget, and cached in the App Group.
//  The document's `createdAt` is ignored.

import Foundation

struct DailyPicks: Codable, Hashable {
    /// The reader's local calendar date, `yyyy-MM-dd`, as in the document's id.
    let date: String
    let poem: DailyPoem
    let shortPoem: DailyPoem
    let poet: DailyPoet

    private enum CodingKeys: String, CodingKey {
        case date, poem, shortPoem, poet
    }
}

/// A whole poem in a daily document, with its text, so it opens without another read.
struct DailyPoem: Codable, Hashable {
    let id: Int
    /// Empty for an untitled poem, which lists by its first line.
    let title: String
    let authorId: Int
    let authorName: String
    let text: String

    var poem: Poem {
        Poem(id: id, title: title, author: Author(id: authorId, name: authorName), content: text)
    }

    /// Lists an untitled poem by its first line.
    var summary: PoemSummary { PoemSummary(poem) }
}

/// One of the poet of the day's best-known poems.
struct DailyPoemRef: Codable, Hashable {
    let id: Int
    let title: String
}

/// The poet of the day.
struct DailyPoet: Codable, Hashable {
    let id: Int
    let name: String
    let poemsCount: Int
    /// The approved photo, absent when the poet has none.
    let photoURL: String?
    let topPoems: [DailyPoemRef]

    var author: Author { Author(id: id, name: name) }

    /// The top poems as list entries. The catalog's other fields are unknown here, and the reader loads the
    /// whole poem by id.
    var topSummaries: [PoemSummary] {
        topPoems.map {
            PoemSummary(id: $0.id, title: $0.title, authorId: id, authorName: name, themeId: nil, createdAt: .distantPast)
        }
    }

    /// The photo's URL when it is an absolute http(s) one.
    var photo: URL? {
        guard let photoURL, let url = URL(string: photoURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}
