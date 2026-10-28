//
//  Item.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation
import SwiftData

@Model
final class PersistedPoem {
    var poemID: Int
    var title: String
    var author: PersistedAuthor
    var text: String
    var persistedDate: Date

    init(poemID: Int, title: String, author: PersistedAuthor, text: String, persistedDate: Date = .now) {
        self.poemID = poemID
        self.title = title
        self.author = author
        self.text = text
        self.persistedDate = persistedDate
    }

    static func toPersistedPoem(from poem: Poem) -> PersistedPoem {
        let persistedPoem = PersistedPoem(
            poemID: poem.id,
            title: poem.title,
            author: PersistedAuthor(authorID: poem.author.id, name: poem.author.name),
            text: poem.content
        )
        return persistedPoem
    }
}
