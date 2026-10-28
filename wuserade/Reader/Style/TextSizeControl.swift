// Minimum iOS 17.
//  Инагъыр: seven dots for the size steps around the reader's Dynamic Type size (the current one in accent),
//  and a rule-outlined pill holding a smaller and a larger 'A'. VoiceOver adjusts it as one value.

import SwiftUI

struct TextSizeControl: View {
    @Binding var step: Int

    private let steps = Array(ReadingStyle.sizeSteps)

    var body: some View {
        HStack(spacing: Space.four) {
            HStack(spacing: Space.two) {
                ForEach(steps, id: \.self) { value in
                    Circle()
                        .fill(value == step ? Palette.accent : Palette.rule)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Инагъыр")
            .accessibilityValue(OwnerCopy.position(index + 1, of: steps.count))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: change(by: 1)
                case .decrement: change(by: -1)
                @unknown default: break
                }
            }

            HStack(spacing: 0) {
                Button { change(by: -1) } label: {
                    Text(verbatim: "A")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: Space.hitMin, height: 36)
                        .contentShape(.rect)
                }
                .accessibilityLabel(OwnerCopy.smaller)
                .disabled(step == steps.first)

                Rectangle()
                    .fill(Palette.rule)
                    .frame(width: 1, height: 20)
                    .accessibilityHidden(true)

                Button { change(by: 1) } label: {
                    Text(verbatim: "A")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: Space.hitMin, height: 36)
                        .contentShape(.rect)
                }
                .accessibilityLabel(OwnerCopy.larger)
                .disabled(step == steps.last)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ink)
            .overlay(Capsule().strokeBorder(Palette.rule))
        }
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    private func change(by delta: Int) {
        step = min(max(step + delta, ReadingStyle.sizeSteps.lowerBound), ReadingStyle.sizeSteps.upperBound)
    }
}
