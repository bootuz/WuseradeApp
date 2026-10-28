// Minimum iOS 17.
//  The poem selected in a regular-width content column, and the list it was selected from.
//  Present in the environment only in regular width; compact lists push the reader instead.

import Observation

@Observable
final class SplitSelection {
    var poemID: Int?
    /// The list the selection came from, for the next-poem row in the detail.
    var context: [PoemSummary] = []

    var readerContext: ReaderContext? {
        guard let poemID else { return nil }
        if let index = context.firstIndex(where: { $0.id == poemID }) {
            return ReaderContext(poems: context, index: index, fromList: false)
        }
        return nil
    }
}
