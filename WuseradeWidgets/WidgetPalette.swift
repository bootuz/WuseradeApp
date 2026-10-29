// Minimum iOS 17.
//  The `Palette` colours the widgets use. The widget has no asset catalog, so each one repeats the colour set's
//  paper, night, paper-ic and night-ic values from `Assets.xcassets/Colors`: change both together.

import SwiftUI
import UIKit

enum WidgetPalette {
    static let page = color(paper: 0xF2F1E6, night: 0x0F131A, paperIC: 0xF2F1E6, nightIC: 0x0A0D12)
    static let ink = color(paper: 0x1C1D18, night: 0xECEAE2, paperIC: 0x0E0F0B, nightIC: 0xF8F6EF)
    static let inkSecondary = color(paper: 0x4C4E45, night: 0xAEB4BF, paperIC: 0x34362F, nightIC: 0xD3D8E0)
    static let inkTertiary = color(paper: 0x5F6157, night: 0x959CA8, paperIC: 0x45473F, nightIC: 0xBAC1CC)
    static let accent = color(paper: 0x245A3F, night: 0x8FD0A8, paperIC: 0x163F2B, nightIC: 0xB0E6C4)
    static let gilt = color(paper: 0x74580F, night: 0xDDBD72, paperIC: 0x57410A, nightIC: 0xEBD293)

    private static func color(paper: UInt32, night: UInt32, paperIC: UInt32, nightIC: UInt32) -> Color {
        Color(UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let rgb = traits.userInterfaceStyle == .dark ? (high ? nightIC : night) : (high ? paperIC : paper)
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
