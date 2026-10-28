// Minimum iOS 17.
//  The poets whose names start with one letter of the Kabardian alphabet.

import Foundation

struct LetterSection: Identifiable {
    let letter: String
    let poets: [Author]

    var id: String { letter }
}
