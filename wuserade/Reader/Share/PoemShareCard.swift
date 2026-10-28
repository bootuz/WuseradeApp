// Minimum iOS 17.
//  The 1080 × 1350 share image, on page: title, poet in ink-secondary (no accent), verse, dateline, then a
//  hairline, the lozenge and 'Усэрадэ' in the wordmark face at 17 in ink-tertiary. ×2.6 up to 7 lines,
//  ×2.0 for 8 to 10; longer poems share their first stanza, capped at 10 lines plus '…'.

import SwiftUI

struct PoemShareCard: View {
    let poem: Poem

    private var summary: PoemSummary { PoemSummary(poem) }
    private var parsed: ParsedPoem { ParsedPoem(poem.content) }

    private var lines: (text: [String], cut: Bool) {
        let all = parsed.lines.map(\.text)
        if all.count <= 10 { return (all, false) }
        let stanza = parsed.firstStanza(minLines: 4, maxLines: 10).poem.lines.map(\.text)
        return (stanza, true)
    }

    var scale: CGFloat { lines.text.count <= 7 ? 2.6 : 2.0 }

    var body: some View {
        let size = CGSize(width: 1080 / scale, height: 1350 / scale)
        VStack(alignment: .leading, spacing: 0) {
            Text(summary.isUntitled ? summary.firstLine + "…" : summary.title)
                .font(SerifStyle.font(.dayTitle, cut: .medium))
                .tracking(0.08 * 26)
                .foregroundStyle(Palette.ink)
            Text(summary.author.name)
                .font(SerifStyle.font(.authorLine, cut: .italic))
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, Space.one)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.text.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.custom(SerifFace.Cut.regular.rawValue, size: 19, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 28, alignment: .leading)
                }
                if lines.cut {
                    Text("…").font(.custom(SerifFace.Cut.regular.rawValue, size: 19, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.top, Space.eight)
            if !lines.cut, let dateline = parsed.dateline {
                Text(dateline)
                    .font(SerifStyle.font(.dateline, cut: .italic))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, 28)
            }
            Spacer(minLength: Space.six)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: Space.two) {
                Lozenge()
                Text("Усэрадэ")
                    .font(.custom(SerifFace.Cut.medium.rawValue, size: 17, relativeTo: .body))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.top, Space.three)
        }
        .padding(40)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Palette.page)
        .dynamicTypeSize(.large)
    }
}
