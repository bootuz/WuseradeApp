// Minimum iOS 17.
//  A daily poem as the app's own models, for the reader and the lists. Kept out of `Shared/DailyPicks.swift`,
//  which the widget compiles without these models.

import Foundation

extension DailyPoem {
    var poem: Poem {
        Poem(id: id, title: title, author: Author(id: authorId, name: authorName), content: text)
    }

    /// Lists an untitled poem by its first line.
    var summary: PoemSummary { PoemSummary(poem) }
}
