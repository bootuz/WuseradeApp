// Minimum iOS 17.
//  A section head: written in sentence case, rendered in small caps, ink-secondary; gilt only for the
//  day's-page label beside its lozenge.

import SwiftUI

struct SectionLabel: View {
    let text: String
    var tone: Tone = .secondary
    var lozenge = false

    enum Tone { case secondary, gilt }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.two) {
            if lozenge {
                Lozenge()
            }
            Text(text)
                .serif(.sectionLabel)
                .foregroundStyle(tone == .gilt ? Palette.gilt : Palette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(KabardianText.sentenceCased(text))
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        SectionLabel(text: "УсэщӀэхэр")
        SectionLabel(text: OwnerCopy.daysPageLabel, tone: .gilt, lozenge: true)
    }
    .padding()
    .background(Palette.page)
}
