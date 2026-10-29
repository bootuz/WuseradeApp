// Minimum iOS 17.
//  A poet's round portrait: the photo when there is one, otherwise the initials on the accent wash.
//  The circle is a fixed size, so the initials are too.

import SwiftUI

struct PoetPortrait: View {
    static let diameter: CGFloat = 128

    let initials: String
    let image: CGImage?
    /// The poet's page uses the default; a list row passes a smaller one, and the initials scale with it.
    var diameter: CGFloat = Self.diameter

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(.circle)
                    .overlay { Circle().strokeBorder(Palette.hairline, lineWidth: 1) }
            } else {
                Circle()
                    .fill(Palette.accentWash)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Text(initials)
                            .font(.custom(SerifFace.Cut.medium.rawValue, fixedSize: 44 * diameter / Self.diameter))
                            .foregroundStyle(Palette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, Space.three)
                    }
            }
        }
        // A photo wider than it is tall is laid out larger than the frame and only clipped, and a clip does not
        // limit touches: the circle alone takes them, and shapes the menu's lifted preview.
        .contentShape([.interaction, .contextMenuPreview], .circle)
    }
}
