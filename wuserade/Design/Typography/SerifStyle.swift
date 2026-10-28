// Minimum iOS 17.
//  Sets a serif type token: the Alegreya cut (swapped under Bold Text), Dynamic Type scaling,
//  small caps, tracking in points and the token's line height.

import SwiftUI

struct SerifStyle: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight
    @ScaledMetric private var scaledSize: CGFloat

    let token: TypeToken
    /// The reader's bold switch: one face heavier, on top of Bold Text.
    var bold: Bool

    init(_ token: TypeToken, bold: Bool = false) {
        self.token = token
        self.bold = bold
        _scaledSize = ScaledMetric(wrappedValue: token.size, relativeTo: token.textStyle)
    }

    private var cut: SerifFace.Cut {
        let boldText = legibilityWeight == .bold
        let base = token.face.cut(heavier: boldText)
        return bold ? base.heavier : base
    }

    func body(content: Content) -> some View {
        content
            .font(SerifStyle.font(token, cut: cut))
            .tracking(token.trackingEm * scaledSize)
            .lineSpacing(lineSpacing)
    }

    /// Extra space that brings the cut's natural line height up to the token's line height.
    private var lineSpacing: CGFloat {
        guard let uiFont = UIFont(name: cut.rawValue, size: scaledSize) else { return 0 }
        return max(0, scaledSize * token.lineHeight / token.size - uiFont.lineHeight)
    }

    static func font(_ token: TypeToken, cut: SerifFace.Cut) -> Font {
        var font = Font.custom(cut.rawValue, size: token.size, relativeTo: token.textStyle)
        if token.smallCaps { font = font.smallCaps() }
        if token.tabularFigures { font = font.monospacedDigit() }
        return font
    }
}

extension View {
    func serif(_ token: TypeToken, bold: Bool = false) -> some View {
        modifier(SerifStyle(token, bold: bold))
    }
}
