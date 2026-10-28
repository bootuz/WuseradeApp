// Minimum iOS 17.
//  Sets verse lines as paragraphs: flush left, ragged right, never justified or hyphenated, tracking 0.
//  Wrapped lines hang at the turnover indent (2em, capped at 25% of the measure); a poet's own indent is
//  kept in 1em steps; a blank source line becomes one stanza gap.
//
//  SwiftUI Text has no head indent and no partial selection on iOS, so this one view is a read-only,
//  selectable UITextView. It also brings the system selection menu with Copy and Share.

import CoreText
import SwiftUI
import UIKit

struct VerseTextView: UIViewRepresentable {
    let lines: [VerseLine]
    /// poemBodyWide (21pt) in regular width, poemBody (19pt) otherwise.
    var wide = false
    var sizeStep = 0
    var leading: ReadingStyle.Leading = .book
    var face: ReadingStyle.Face = .alegreya
    var bold = false
    /// The measure the turnover cap is taken from.
    var measure: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    func makeUIView(context: Context) -> UITextView {
        let view = VerseUITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.adjustsFontForContentSizeCategory = false
        view.dataDetectorTypes = []
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLanguage = "kbd"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = attributedText()
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? measure
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    private func attributedText() -> NSAttributedString {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let metrics = UIFontMetrics(forTextStyle: .body)
        let base = (wide ? 21 : 19) + CGFloat(sizeStep) * ReadingStyle.pointsPerStep
        let size = metrics.scaledValue(for: base, compatibleWith: traits)
        let lineHeight = (size * leading.multiple).rounded()
        let em = size
        let turnover = min(Space.turnoverEm * em, measure * 0.25)
        let weightSteps = (bold ? 1 : 0) + (legibilityWeight == .bold ? 1 : 0)

        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.alignment = .natural
            paragraph.hyphenationFactor = 0
            paragraph.lineBreakMode = .byWordWrapping
            // A part head already leaves a stanza gap after itself; adding the next line's gap would double it.
            let followsPartHead = index > 0 && lines[index - 1].kind == .partHead
            paragraph.paragraphSpacingBefore = line.gapBefore && index > 0 && !followsPartHead ? lineHeight : 0

            var font = verseFont(size: size, weightSteps: weightSteps)
            var color = UIPalette.ink
            var kern: CGFloat = 0
            var text = line.text

            switch line.kind {
            case .verse(let steps):
                let indent = CGFloat(steps) * Space.indentStepEm * em
                paragraph.firstLineHeadIndent = indent
                paragraph.headIndent = indent + turnover
            case .prose where !followsPartHead:
                paragraph.paragraphSpacingBefore = max(paragraph.paragraphSpacingBefore, line.gapBefore ? lineHeight : lineHeight / 2)
            case .prose:
                break
            case .omission:
                color = UIPalette.inkTertiary
            case .partHead:
                let partSize = metrics.scaledValue(for: 17, compatibleWith: traits)
                font = smallCapsFont(UIFont(name: SerifFace.Cut.medium.rawValue, size: partSize) ?? .systemFont(ofSize: partSize))
                color = UIPalette.inkSecondary
                kern = 0.1 * partSize
                text = text.lowercased()
                paragraph.paragraphSpacingBefore = index > 0 ? lineHeight : 0
                paragraph.paragraphSpacing = lineHeight
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern,
                .accessibilitySpeechLanguage: "kbd"
            ]
            result.append(NSAttributedString(string: text + (index < lines.count - 1 ? "\n" : ""), attributes: attributes))
        }
        return result
    }

    /// Alegreya Regular, one face heavier for the bold switch or Bold Text, two when both are on.
    private func verseFont(size: CGFloat, weightSteps: Int) -> UIFont {
        switch face {
        case .system:
            let weight: UIFont.Weight = weightSteps >= 2 ? .bold : weightSteps == 1 ? .medium : .regular
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .alegreya:
            let cut: SerifFace.Cut = weightSteps >= 2 ? .bold : weightSteps == 1 ? .medium : .regular
            return UIFont(name: cut.rawValue, size: size) ?? .systemFont(ofSize: size)
        }
    }

    private func smallCapsFont(_ font: UIFont) -> UIFont {
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kLowerCaseType, .selector: kLowerCaseSmallCapsSelector],
            [.type: kUpperCaseType, .selector: kUpperCaseSmallCapsSelector]
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: features])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
