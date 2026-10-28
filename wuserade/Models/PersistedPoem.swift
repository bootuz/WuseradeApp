//
//  Item.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation
import SwiftData

/// A like kept on the device before likes moved to Firestore. Nothing writes these any more;
/// `LegacyLikesMigrator` uploads them once.
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
}
