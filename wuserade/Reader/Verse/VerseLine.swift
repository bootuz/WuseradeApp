// Minimum iOS 17.
//  One source line of a poem, after parsing.

import Foundation

struct VerseLine: Hashable {
    enum Kind: Hashable {
        /// A verse line, with the poet's own indent in steps (at most six).
        case verse(indentSteps: Int)
        /// A Roman-numeral part head.
        case partHead
        /// A dotted omission row, shown as '. . .'.
        case omission
        /// A line over 80 characters, set as a prose paragraph without the hanging indent.
        case prose
    }

    var kind: Kind
    var text: String
    /// One stanza gap before this line, for a run of blank source lines.
    var gapBefore: Bool
}
