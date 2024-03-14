//
//  Poem.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

struct Poem: Codable, Identifiable, Hashable, Copyable {
    let id: Int
    let title: String
    let author: Author
    let content: String

    static var example: Poem {
        return Poem(id: 1, title: "Усэм и цlэр", author: Author(id: 1, name: "Усакlуэм и цlэр"), content: """
            Тхыпхъэм и щапхъэу
            Мыбдеж усэм и едзыгъуэ къиувэнущ,
            И инагъым зэрызихъуэжыр
            Абы нэрылъагъуу къридзэнущ
            """
        )
    }

    var copyableText: String {
        return "\(title)\n\(author.name)\n\n\(content)"
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
