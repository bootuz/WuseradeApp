// Minimum iOS 17.
//  The poet of the day as the app's own models, for Home and the poet's page. Kept out of
//  `Shared/DailyPicks.swift`, which the widget compiles without these models.

import Foundation

extension DailyPoet {
    var author: Author { Author(id: id, name: name) }

    /// The top poems as list entries. The catalog's other fields are unknown here, and the reader loads the
    /// whole poem by id.
    var topSummaries: [PoemSummary] {
        topPoems.map {
            PoemSummary(id: $0.id, title: $0.title, authorId: id, authorName: name, themeId: nil, createdAt: .distantPast)
        }
    }
}
