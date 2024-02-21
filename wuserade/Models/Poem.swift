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
            IэгупIэ хуит вокзалым хэткъым
            КIэрысщ щхьэгъубжэ абджым нищэ
            Кассирым сэ билет къызищэм
            СыщIыхуеяр и щIыбым теткъым.

            Билетым тетми сыпылъкъым,
            Къыпылъэдати къызощэху.
            БампIэгъуэщ. ТщIэркъым ди щхьэм илъыр,
            Мыр махуэ хьэлъэу къэунэхут.

            Сыдаш къалэшхуэм шэрхъ зэрыхьхэм,
            Бзииху кIэхухэм гъуэгур зэкIуэцIах,
            Сызэгуагъэпми винт зэрышххэм,
            Нагъэшхэу жыгхэм зыкърах.

            Билетым теттэкъым... ИтIани
            Къыпылъэдати сыкъэсащ...
            Мэз тхьэхум си пщэр итIэтауэ,
            КъыхуещIыр ба си бгъэч есам.

            Трегъэгушхуэ си тхьэмбылыр,
            Къысхуегъэплъэжыр нэ хуэлар,
            КъысхуегъэтIылъыр мылъку бгъэдэлъыр
            ЩхъуантIагъэ, уэшхкIэ гъэхулIар!
            """
        )
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
