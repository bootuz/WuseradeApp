// Minimum iOS 17.
//  Normalises Kabardian text for display and search. The palochka is always Ӏ (U+04C0): Alegreya draws
//  U+04CF almost exactly like a Latin l, and the server text mixes U+04CF, U+0406 and Latin I, l and 1.

import Foundation

enum KabardianText {
    static let palochka: Character = "\u{04C0}"

    /// Display form: palochka folded to Ӏ, U+200B stripped, double spaces collapsed, spaced hyphens and en dashes
    /// between words turned into a no-break space plus an em dash, CRLF turned into LF.
    static func normalized(_ text: String) -> String {
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(isRomanNumeralLine(line) ? String(line) : normalizedLine(String(line)))
        }
        return lines.joined(separator: "\n")
    }

    /// A title for display: normalised, with a trailing run of three or more dots (or dots before '…') turned
    /// into one '…'. The source's case is kept.
    static func title(_ title: String) -> String {
        normalized(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\.*(\\.{3}|…)$", with: "…", options: .regularExpression)
    }

    /// Sentence case for VoiceOver, so a small-caps title such as 'ПСЫ ЦӀЫКӀУ' is read as 'Псы цӀыкӀу'.
    static func sentenceCased(_ text: String) -> String {
        let lowered = normalized(text).lowercased().replacingOccurrences(of: "\u{04CF}", with: String(palochka))
        guard let first = lowered.first else { return lowered }
        return first.uppercased() + lowered.dropFirst()
    }

    /// One key for every way people type the palochka, so 'цIык' finds 'ПСЫ ЦӀЫКӀУ'.
    static func searchKey(_ text: String) -> String {
        var key = ""
        for character in text {
            switch character {
            case "\u{04C0}", "\u{04CF}", "\u{0406}", "\u{0456}", "I", "l", "1": key.append("\u{04CF}")
            default: key.append(contentsOf: character.lowercased())
            }
        }
        return key
    }

    private static func normalizedLine(_ line: String) -> String {
        let characters = Array(line.replacingOccurrences(of: "\u{200B}", with: ""))
        var output = ""
        for (index, character) in characters.enumerated() {
            switch character {
            case "\u{04CF}", "\u{0406}":
                output.append(palochka)
            case "I", "l", "1":
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                output.append(isCyrillicLetter(previous) || isCyrillicLetter(next) ? palochka : character)
            default:
                output.append(character)
            }
        }
        // Leading spaces are the poet's own indent; only spaces inside the line collapse.
        let indent = String(output.prefix { $0 == " " || $0 == "\t" })
        var rest = String(output.dropFirst(indent.count))
        while rest.contains("  ") { rest = rest.replacingOccurrences(of: "  ", with: " ") }
        rest = rest.replacingOccurrences(of: " – ", with: "\u{00A0}— ")
        rest = rest.replacingOccurrences(of: " - ", with: "\u{00A0}— ")
        return indent + rest
    }

    private static func isCyrillicLetter(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        return (0x0400...0x04FF).contains(scalar.value) && character?.isLetter == true
    }

    /// Part heads such as 'II' or 'XIV' are left alone.
    private static func isRomanNumeralLine(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { "IVXLC".contains($0) }
    }
}

extension String {
    /// Display form of Kabardian text from the server.
    var kbd: String { KabardianText.normalized(self) }
}
