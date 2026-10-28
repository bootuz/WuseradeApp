//
//  PersistedAuthor.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 14.03.2024.
//

import Foundation
import SwiftData

@Model
final class PersistedAuthor {
    var authorID: Int
    var name: String

    init(authorID: Int, name: String) {
        self.authorID = authorID
        self.name = name
    }
}
