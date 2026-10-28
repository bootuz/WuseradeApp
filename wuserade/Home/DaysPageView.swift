// Minimum iOS 17.
//  The day's page: a head row (gilt lozenge, label, date) over a hairline, the title and poet, the verse, and
//  Like and Share. A poem over 8 lines shows its first stanza (at most 8 lines) and a link to read on.

import SwiftUI

struct DaysPageView: View {
    let poem: Poem
    var date: Date = .now
    var onOpen: () -> Void

    @Environment(\.navigate) private var navigate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var stanzaGap: CGFloat = 28

    private static let excerptLines = 8
    /// A one-line subtitle or a part number alone would make a thin page, so the excerpt runs on to 4 lines.
    private static let excerptMinLines = 4

    var body: some View {
        let summary = PoemSummary(poem)
        let parsed = ParsedPoem(poem.content)
        let excerpt = parsed.firstStanza(minLines: Self.excerptMinLines, maxLines: Self.excerptLines)
        let excerpted = parsed.lineCount > Self.excerptLines

        VStack(alignment: .leading, spacing: 0) {
            head
            PoemTitleBlock(poem: summary, large: true, onTitle: onOpen) {
                navigate(.poet(summary.author))
            }
            .padding(.top, Space.six)

            VerseView(poem: excerpted ? excerpt.poem : parsed, showDateline: !excerpted)
                .padding(.top, Space.eight)

            if excerpted {
                Button(action: onOpen) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.one) {
                        Text(OwnerCopy.readOn).serif(.authorLine)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: Space.hitMin)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.top, Space.three)
            } else if !summary.isUntitled {
                Lozenge().padding(.top, stanzaGap)
            }

            HStack(spacing: Space.six) {
                LikeButton(poem: poem)
                ShareLink(item: PoemShare(poem: poem), preview: SharePreview(summary.isUntitled ? summary.firstLine : summary.title)) {
                    Label("Дэгуэшэн", systemImage: "square.and.arrow.up")
                }
                .foregroundStyle(Palette.ink)
            }
            .labelStyle(.iconOnly)
            // Borderless: inside a List row, default-style buttons all fire on a tap anywhere in the row.
            .buttonStyle(.borderless)
            .font(.title3)
            .frame(minHeight: Space.hitMin)
            .padding(.top, Space.six)

            Rectangle().fill(Palette.hairline).frame(height: 1)
                .padding(.top, Space.six)
        }
    }

    /// '28.10', whatever the device's region.
    private var dayAndMonth: String {
        let parts = Calendar.current.dateComponents([.day, .month], from: date)
        return String(format: "%02d.%02d", parts.day ?? 0, parts.month ?? 0)
    }

    private var head: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.one))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.two))
        return VStack(alignment: .leading, spacing: Space.three) {
            layout {
                SectionLabel(text: OwnerCopy.daysPageLabel, tone: .gilt, lozenge: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(verbatim: dayAndMonth)
                    .serif(.folio)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityLabel(OwnerCopy.dayAndMonth(date))
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}
