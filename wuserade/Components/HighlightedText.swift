// Minimum iOS 17.
//  Serif text whose search matches are set one face heavier than the row's own style, in the row's colour,
//  with accent-wash behind them as reinforcement only. Matching folds every palochka variant.

import SwiftUI

struct HighlightedText: View {
    let text: String
    let query: String
    let token: TypeToken

    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        Text(attributed)
            .serif(token)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let needle = KabardianText.searchKey(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return result }

        // One key character per source character, so offsets map straight back.
        let characters = Array(text)
        let keys = characters.map { KabardianText.searchKey(String($0)).first ?? $0 }
        let needleKeys = Array(needle)
        guard needleKeys.count <= keys.count else { return result }

        let base = token.face.cut(heavier: legibilityWeight == .bold)
        let matchFont = SerifStyle.font(token, cut: base.heavier)
        var start = 0
        while start + needleKeys.count <= keys.count {
            if Array(keys[start..<start + needleKeys.count]) == needleKeys {
                let lower = result.index(result.startIndex, offsetByCharacters: start)
                let upper = result.index(lower, offsetByCharacters: needleKeys.count)
                result[lower..<upper].font = matchFont
                result[lower..<upper].backgroundColor = Palette.accentWash
                start += needleKeys.count
            } else {
                start += 1
            }
        }
        return result
    }
}
