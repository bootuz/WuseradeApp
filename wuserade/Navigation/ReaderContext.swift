// Minimum iOS 17.
//  The list a poem was opened from, so the reader can page through it and offer the next poem.

import Foundation

struct ReaderContext: Hashable {
    var poems: [PoemSummary]
    var index: Int
    /// The folio '12 / 46' shows only when the poem was opened from a list.
    var fromList: Bool

    init(poems: [PoemSummary], index: Int, fromList: Bool = true) {
        self.poems = poems
        self.index = min(max(index, 0), max(poems.count - 1, 0))
        self.fromList = fromList
    }

    /// A single poem opened from the day's page, a link or a widget.
    init(single poem: PoemSummary) {
        self.init(poems: [poem], index: 0, fromList: false)
    }

    var current: PoemSummary? { poems.indices.contains(index) ? poems[index] : nil }

    func next(after index: Int) -> PoemSummary? {
        poems.indices.contains(index + 1) ? poems[index + 1] : nil
    }
}
