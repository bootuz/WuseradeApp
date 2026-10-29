// Minimum iOS 17.
//  The poet of the day on Home: a label, the portrait (or initials), the name and poem count, the poet's three
//  best-known poems and a link to all their poems. Emits list rows, so it sits inside Home's List.

import SwiftUI

struct PoetOfTheDaySection: View {
    let poet: DailyPoet

    @Environment(\.navigate) private var navigate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loaded: (url: URL, image: CGImage)?

    private static let portraitDiameter: CGFloat = 58

    var body: some View {
        let summaries = poet.topSummaries

        SectionLabel(text: OwnerCopy.poetOfTheDay)
            .padding(.top, Space.six)
            .contentRow(separator: .hidden)

        Button { openPoet() } label: { card }
            .buttonStyle(.plain)
            .contentRow(separator: .hidden)

        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
            Button {
                AnalyticsManager.shared.dailyOpen(source: "home_poet")
                navigate(.reader(ReaderContext(poems: summaries, index: index)))
            } label: {
                HStack(spacing: Space.two) {
                    PoemRowLabel(poem: summary, subtitle: .none)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contentRow()
        }

        Button { openPoet() } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.one) {
                Text(OwnerCopy.allTheirPoems).serif(.authorLine)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.accent)
            .frame(minHeight: Space.hitMin, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contentRow(separator: .hidden)
    }

    private func openPoet() {
        AnalyticsManager.shared.dailyOpen(source: "home_poet")
        navigate(.poet(poet.author))
    }

    private var card: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.three))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.three))
        return layout {
            portrait
            VStack(alignment: .leading, spacing: Space.half) {
                Text(poet.name)
                    .serif(.rowName)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(poet.poemsCount) \(OwnerCopy.countNoun)")
                    .serif(.rowMeta)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(poet.name), \(poet.poemsCount) \(OwnerCopy.countNoun)")
        .accessibilityAddTraits(.isButton)
        .task(id: poet.photo) {
            guard let url = poet.photo, loaded?.url != url,
                  let photo = try? await PortraitLoader.image(at: url) else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) {
                loaded = (url, photo)
            }
        }
    }

    private var portrait: some View {
        let image = loaded.flatMap { $0.url == poet.photo ? $0.image : nil }
        return PoetPortrait(initials: PoetInitials.of(poet.name), image: image, diameter: Self.portraitDiameter)
    }
}
