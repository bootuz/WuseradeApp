// Minimum iOS 17.
//  Every button we draw is a capsule. Primary: accent fill with an on-accent label.
//  Secondary: accent-wash fill with an accent label.

import SwiftUI

struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(kind == .primary ? Palette.onAccent : Palette.accent)
            .padding(.horizontal, Space.six)
            .padding(.vertical, Space.three)
            .frame(minHeight: Space.hitMin)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(kind == .primary ? Palette.accent : Palette.accentWash, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    static var primaryCapsule: CapsuleButtonStyle { CapsuleButtonStyle(kind: .primary) }
    static var secondaryCapsule: CapsuleButtonStyle { CapsuleButtonStyle(kind: .secondary) }
    static func primaryCapsule(fullWidth: Bool) -> CapsuleButtonStyle { CapsuleButtonStyle(kind: .primary, fullWidth: fullWidth) }
}
