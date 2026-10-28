// Minimum iOS 17.
//  The Kabardian alphabet, digraphs and trigraphs included, written with Ӏ (U+04C0).
//  Sorts and groups names the way the design system does: the longest letter that matches wins.

import Foundation

enum KabardianAlphabet {
    static let letters: [String] = [
        "А", "Э", "Б", "В", "Г", "ГУ", "ГЪ", "ГЪУ", "Д", "ДЖ", "ДЗ", "Е", "Ё", "Ж", "ЖЬ", "З", "И", "Й",
        "К", "КУ", "КӀ", "КӀУ", "КЪ", "КЪУ", "КХЪ", "КХЪУ", "Л", "ЛЪ", "ЛӀ", "М", "Н", "О", "П", "ПӀ", "Р",
        "С", "Т", "ТӀ", "У", "Ф", "ФӀ", "Х", "ХУ", "ХЬ", "ХЪ", "ХЪУ", "Ц", "ЦӀ", "Ч", "Ш", "Щ", "ЩӀ",
        "Ы", "Ъ", "Ь", "Ю", "Я", "Ӏ", "ӀУ"
    ]

    private static let rank: [String: Int] = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($1, $0) })

    private struct Letter {
        let rank: Double
        let range: Range<String.Index>
    }

    /// The section letter of a name in its own spelling: 'КӀ', 'Къ', 'Хь'.
    static func sectionLetter(of name: String) -> String {
        let text = name.kbd.trimmingCharacters(in: .whitespaces)
        guard let first = letters(in: text).first else { return "" }
        let letter = String(text[first.range])
        return letter.prefix(1).uppercased() + letter.dropFirst().lowercased()
            .replacingOccurrences(of: "\u{04CF}", with: "\u{04C0}")
    }

    /// Alphabet order, letter by letter, then shorter first.
    static func precedes(_ a: String, _ b: String) -> Bool {
        let x = letters(in: a.kbd), y = letters(in: b.kbd)
        for (l, r) in zip(x, y) where l.rank != r.rank {
            return l.rank < r.rank
        }
        return x.count < y.count
    }

    private static func letters(in text: String) -> [Letter] {
        let upper = text.uppercased().replacingOccurrences(of: "\u{04CF}", with: "\u{04C0}")
        var result: [Letter] = []
        var index = upper.startIndex
        while index < upper.endIndex {
            var matched = false
            for length in stride(from: 4, through: 1, by: -1) {
                guard let end = upper.index(index, offsetBy: length, limitedBy: upper.endIndex) else { continue }
                if let r = rank[String(upper[index..<end])] {
                    result.append(Letter(rank: Double(r), range: index..<end))
                    index = end
                    matched = true
                    break
                }
            }
            guard !matched else { continue }
            let character = upper[index]
            let next = upper.index(after: index)
            if character.isWhitespace {
                if let last = result.last, last.rank != -2 { result.append(Letter(rank: -2, range: index..<next)) }
            } else if let digit = character.wholeNumberValue {
                result.append(Letter(rank: -1 + Double(digit) / 100, range: index..<next))
            } else if character.isLetter {
                result.append(Letter(rank: 1000 + Double(character.unicodeScalars.first?.value ?? 0), range: index..<next))
            }
            index = next
        }
        while result.last?.rank == -2 { result.removeLast() }
        return result
    }
}
