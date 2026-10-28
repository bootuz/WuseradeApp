// Minimum iOS 17.
//  Shown once on first launch, and the reader can dismiss it. Three entries between hairlines like a contents
//  page. No sign-in step and no notification request afterwards.

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Усэрадэ")
                        .serif(.wordmark)
                        .foregroundStyle(Palette.ink)
                    Text("Къеблагъэ Усэрадэм!")
                        .serif(.prose)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, Space.two)

                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                        entry(String(localized: "Адыгэ усыгъэм хэгъуазэ"), OwnerCopy.onboardingFirstLine)
                        entry(String(localized: "Усэхэр зытеухуам еплъ"), String(localized: "ЗэмылӀэужыгъуэу къыхэтхащ"))
                        entry(String(localized: "УсакӀуэхэр зэгъэцӀыху"), String(localized: "Я лэжьыгъэхэм нэӀуасэ зыхуэщӀ"))
                    }
                    .padding(.top, Space.eight)
                }
                .padding(.horizontal, Space.readingMargin)
                .padding(.top, Space.sixteen)
            }

            Button("Хъуащ") { dismiss() }
                .buttonStyle(.primaryCapsule(fullWidth: true))
                .padding(.horizontal, Space.readingMargin)
                .padding(.bottom, Space.four)
        }
        .background(Palette.page)
        .presentationBackground(Palette.page)
    }

    private func entry(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(title)
                .serif(.rowTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(KabardianText.sentenceCased(title))
            Text(line)
                .serif(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
            Rectangle().fill(Palette.hairline).frame(height: 1)
                .padding(.top, Space.three)
        }
        .padding(.top, Space.three)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView()
}
