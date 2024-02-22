//
//  Poem.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

struct AllPoems: Codable {
    let poems: [Poem]
    let totalPages: Int
    let currentPage: String
}

struct Poem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let author: Author
    let content: String

    static var example: Poem {
        return Poem(id: 1, title: "Усэм и цlэр", author: Author(id: 1, name: "Усакlуэм и цlэр"), content: """
            Усэ lыхьэм и щапхъэ цlыкlу
            Мыбдежым усэм и тхыпхъэ 
            щапхъэр нэрылъагъуу къытридзэнущ,
            икlи и инагъри зарызихъуэжыр.
            """
        )
    }

    static func toPoem(from persisted: PersistedPoem) -> Poem {
        let poem = Poem(
            id: persisted.poemID,
            title: persisted.title,
            author: Author(id: persisted.author.authorID, name: persisted.author.name),
            content: persisted.text
        )
        return poem
    }
}


struct Author: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct AllAuthors: Codable {
    let authors: [Author]
    let totalPages: Int
    let currentPage: String
}
