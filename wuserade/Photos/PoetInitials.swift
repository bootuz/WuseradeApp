// Minimum iOS 17.
//  The letters in the portrait circle of a poet with no photo: the first Kabardian letter of each of the first
//  two words of the name. Digraphs and trigraphs count as one letter, so 'Хьа Бэ' gives 'ХьБ'.

import Foundation

enum PoetInitials {
    static func of(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .map { KabardianAlphabet.sectionLetter(of: String($0)) }
            .joined()
    }
}
