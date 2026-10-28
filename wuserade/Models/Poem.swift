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
        return Poem(id: 1, title: "Усэм и цӀэр", author: Author(id: 1, name: "УсакӀуэм и цӀэр"), content: """
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
}
