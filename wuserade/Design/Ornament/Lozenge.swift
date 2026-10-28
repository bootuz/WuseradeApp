// Minimum iOS 17.
//  The only ornament. 6 × 9pt at poemBody, the asterism 16 × 19pt, ×2 in empty states and on the Update cover.
//  Hidden from VoiceOver unless it heads an untitled poem, where it carries the first line as its label.

import SwiftUI

struct Lozenge: View {
    enum Kind { case single, asterism }

    var kind: Kind = .single
    var scale: CGFloat = 1
    /// Set only when the asterism stands in for a title.
    var headerLabel: String?

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        let size = kind == .single ? CGSize(width: 6, height: 9) : CGSize(width: 16, height: 19)
        LozengeShape(asterism: kind == .asterism)
            .fill(Palette.gilt)
            .frame(width: size.width * unit * scale, height: size.height * unit * scale)
            .accessibilityHidden(headerLabel == nil)
            .accessibilityLabel(headerLabel ?? "")
            .accessibilityAddTraits(headerLabel == nil ? [] : .isHeader)
    }
}

#Preview {
    HStack(spacing: 24) {
        Lozenge()
        Lozenge(kind: .asterism)
        Lozenge(kind: .asterism, scale: 2)
    }
    .padding()
    .background(Palette.page)
}
