// Minimum iOS 17.
//  A parsed poem's verse: text runs, gilt asterisms for section breaks, and the dateline.
//  Long poems (over 200 lines) render lazily, one stanza per text view.

import SwiftUI

struct VerseView: View {
    let poem: ParsedPoem
    var wide = false
    var showDateline = true

    @AppStorage(ReadingStyle.Key.sizeStep) private var sizeStep = 0
    @AppStorage(ReadingStyle.Key.leading) private var leading: ReadingStyle.Leading = .book
    @AppStorage(ReadingStyle.Key.face) private var face: ReadingStyle.Face = .alegreya
    @AppStorage(ReadingStyle.Key.bold) private var bold = false

    @ScaledMetric(relativeTo: .body) private var stanzaGap: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var em: CGFloat = 19

    private static let lazyThreshold = 200

    var body: some View {
        let measure = (wide ? em * 21 / 19 : em) * Space.measureMaxEm
        VStack(alignment: .leading, spacing: 0) {
            // One lazy stack for the whole poem. A stack per section numbered each section's stanzas from 0, and
            // lazy stacks sharing ids in one scroll view showed an earlier section in place of a later one.
            if poem.lineCount > Self.lazyThreshold {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(poem.lazyRows.enumerated()), id: \.offset) { _, row in
                        // One view per row whichever kind it is, so the stack can identify rows by id alone.
                        VStack(alignment: .leading, spacing: 0) {
                            switch row {
                            case .asterism: asterism
                            case .lines(let stanza): text(stanza, measure: measure)
                            }
                        }
                    }
                }
            } else {
                ForEach(Array(poem.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .asterism: asterism
                    case .lines(let lines): text(lines, measure: measure)
                    }
                }
            }
            if showDateline, let dateline = poem.dateline {
                Text(dateline)
                    .serif(.dateline)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, stanzaGap)
            }
        }
        // Regular width: as wide as the longest line, capped at the measure, so the centred block
        // hangs from its own left edge.
        .frame(width: wide ? min(longestLine, measure) : nil, alignment: .leading)
        .frame(maxWidth: measure, alignment: .leading)
    }

    private var longestLine: CGFloat {
        let size = (wide ? em * 21 / 19 : em) + CGFloat(sizeStep) * ReadingStyle.pointsPerStep
        let cut: SerifFace.Cut = bold ? .medium : .regular
        let font = face == .system ? UIFont.systemFont(ofSize: size) : (UIFont(name: cut.rawValue, size: size) ?? .systemFont(ofSize: size))
        let widths = poem.lines.map { line -> CGFloat in
            var indent: CGFloat = 0
            if case .verse(let steps) = line.kind { indent = CGFloat(steps) * size }
            return (line.text as NSString).size(withAttributes: [.font: font]).width + indent
        }
        let dateline = poem.dateline.map { ($0 as NSString).size(withAttributes: [.font: font]).width } ?? 0
        // A little slack: TextKit lays a line out a point or two wider than NSString measures it, and the
        // longest line must never wrap.
        return ceil(max(widths.max() ?? 0, dateline)) + 4
    }

    private func text(_ lines: [VerseLine], measure: CGFloat) -> some View {
        VerseTextView(lines: lines, wide: wide, sizeStep: sizeStep, leading: leading, face: face, bold: bold, measure: measure)
    }

    private var asterism: some View {
        Lozenge(kind: .asterism)
            .padding(.vertical, stanzaGap)
    }
}
