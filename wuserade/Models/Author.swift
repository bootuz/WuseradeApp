//
//  Author.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation

struct Author: Codable, Identifiable, Hashable {
    let id: Int
    let name: String

    /// True for the catalog's placeholder author of poems with no known poet, whatever the case or the
    /// palochka spelling.
    var isUnknownAuthor: Bool {
        KabardianText.searchKey(name) == Self.unknownAuthorKey
    }

    private static let unknownAuthorKey = KabardianText.searchKey("Зытхар тщ\u{04C0}экъым")
}
