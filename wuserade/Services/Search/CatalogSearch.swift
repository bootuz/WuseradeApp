import Foundation

/// On-device search over catalog entries. Case-insensitive and tolerant of the several ways
/// Kabardian users type the palochka (`ӏ`).
enum CatalogSearch {
    /// Canonical palochka (U+04CF, Cyrillic small letter palochka).
    private static let palochka: Unicode.Scalar = "\u{04CF}"

    /// Everything people type in place of the palochka: the capital and small palochka (U+04C0, U+04CF),
    /// Latin `I`/`i`, Latin `l` and the digit `1`. Lowercasing runs first, but both cases are listed so the
    /// set stands on its own.
    private static let palochkaVariants: Set<Unicode.Scalar> = [
        "\u{04C0}", "\u{04CF}", "I", "i", "l", "1",
    ]

    /// Lowercases, maps every palochka variant to the canonical `ӏ`, and trims surrounding whitespace.
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            scalars.append(palochkaVariants.contains(scalar) ? palochka : scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Entries whose title or author name contains `query`.
    /// Ranked: title starts with the query, then other title matches, then author-only matches;
    /// each group ordered by title. A blank query matches nothing.
    static func search(_ query: String, in entries: [PoemSummary]) -> [PoemSummary] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }

        // Rank 0: title prefix, 1: title elsewhere, 2: author name only.
        var ranked: [(rank: Int, title: String, entry: PoemSummary)] = []
        for entry in entries {
            let title = normalize(entry.title)
            if title.hasPrefix(needle) {
                ranked.append((0, title, entry))
            } else if title.contains(needle) {
                ranked.append((1, title, entry))
            } else if normalize(entry.authorName).contains(needle) {
                ranked.append((2, title, entry))
            }
        }

        ranked.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.entry.id < $1.entry.id
        }
        return ranked.map(\.entry)
    }
}
