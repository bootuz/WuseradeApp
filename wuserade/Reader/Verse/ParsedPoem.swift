// Minimum iOS 17.
//  A poem's text set for reading: blocks of lines and section breaks, plus the trailing year line.
//  Never invents stanzas: only blank source lines make gaps, and runs of them collapse to one.

import Foundation

struct ParsedPoem: Hashable {
    var blocks: [VerseBlock]
    var dateline: String?

    /// All verse lines, ignoring breaks.
    var lines: [VerseLine] {
        blocks.flatMap { block -> [VerseLine] in
            if case .lines(let lines) = block { return lines }
            return []
        }
    }

    var lineCount: Int { lines.count }

    init(blocks: [VerseBlock], dateline: String?) {
        self.blocks = blocks
        self.dateline = dateline
    }

    init(_ text: String) {
        let raw = text.kbd.replacingOccurrences(of: "\u{00A0}\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        var trimmed = raw[...]
        while trimmed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed = trimmed.dropFirst() }
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed = trimmed.dropLast() }

        var dateline: String?
        if trimmed.count > 1, let last = trimmed.last?.trimmingCharacters(in: .whitespaces), Self.isDateline(last) {
            dateline = last.replacingOccurrences(of: "\\s*[-–—]\\s*$", with: "", options: .regularExpression)
            trimmed = trimmed.dropLast()
            while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { trimmed = trimmed.dropLast() }
        }

        var blocks: [VerseBlock] = []
        var current: [VerseLine] = []
        var pendingGap = false
        for line in trimmed {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { pendingGap = true; continue }
            if Self.isAsterism(text) {
                if !current.isEmpty { blocks.append(.lines(current)); current = [] }
                blocks.append(.asterism)
                pendingGap = false
                continue
            }
            let gap = pendingGap && !current.isEmpty
            pendingGap = false
            if Self.isOmission(text) {
                current.append(VerseLine(kind: .omission, text: ". . .", gapBefore: gap))
            } else if Self.isPartHead(text) {
                current.append(VerseLine(kind: .partHead, text: text.trimmingCharacters(in: CharacterSet(charactersIn: ".")), gapBefore: gap))
            } else {
                let spoken = text.replacingOccurrences(of: "^[-–—]\\s+", with: "— ", options: .regularExpression)
                let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.count
                let steps = leadingSpaces == 0 ? 0 : min(6, max(1, leadingSpaces / 2))
                current.append(VerseLine(kind: spoken.count > 80 ? .prose : .verse(indentSteps: steps), text: spoken, gapBefore: gap))
            }
        }
        if !current.isEmpty { blocks.append(.lines(current)) }
        self.init(blocks: blocks, dateline: dateline)
    }

    /// The opening stanza, capped at `maxLines`. A stanza shorter than `minLines`, such as a one-line subtitle
    /// or a part number, runs on into the next stanzas until there are `minLines`.
    func firstStanza(minLines: Int = 1, maxLines: Int = 8) -> (poem: ParsedPoem, isExcerpt: Bool) {
        let all = lines
        var kept: [VerseLine] = []
        for (index, line) in all.enumerated() {
            if index > 0 && line.gapBefore && kept.count >= minLines { break }
            if kept.count >= maxLines { break }
            kept.append(line)
        }
        let breaksFirst = blocks.first == .asterism
        let isExcerpt = kept.count < all.count || breaksFirst || blocks.count > 1
        return (ParsedPoem(blocks: kept.isEmpty ? [] : [.lines(kept)], dateline: isExcerpt ? nil : dateline), isExcerpt)
    }

    private static func isDateline(_ text: String) -> Bool {
        text.range(of: "^\\(?\\d{3,4}(\\s*[-–—]\\s*\\d{2,4})?\\s*(гъ\\.?|г\\.?)?\\s*\\)?\\s*[-–—]?\\s*$", options: .regularExpression) != nil
    }

    private static func isAsterism(_ text: String) -> Bool {
        text.range(of: "^(\\*\\s*){3}$", options: .regularExpression) != nil
    }

    private static func isOmission(_ text: String) -> Bool {
        text.range(of: "^[.…\\s]{3,}$", options: .regularExpression) != nil
    }

    private static func isPartHead(_ text: String) -> Bool {
        text.range(of: "^[IVXLC]{1,6}\\.?$", options: .regularExpression) != nil
    }
}
