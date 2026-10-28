// Minimum iOS 17.
//  The reader's own settings from the Aa sheet. Stored in UserDefaults under `ReadingStyle.Key`.
//  The old FontSettings (MarckScript, Georgia, point sizes, character spacing) do not map onto these,
//  so every reader starts at the defaults.

import CoreGraphics

enum ReadingStyle {
    enum Key {
        static let sizeStep = "reading.sizeStep"
        static let leading = "reading.leading"
        static let face = "reading.face"
        static let bold = "reading.bold"
    }

    /// −2 to +4 steps of 2pt on the verse's base size, which Dynamic Type then scales.
    static let sizeSteps = -2...4
    static let pointsPerStep: CGFloat = 2

    enum Leading: String, CaseIterable, Identifiable {
        case compact, book, airy

        var id: Self { self }

        /// Line height as a multiple of the verse size.
        var multiple: CGFloat {
            switch self {
            case .compact: 1.33
            case .book: 1.47
            case .airy: 1.70
            }
        }

        var title: String {
            switch self {
            case .compact: OwnerCopy.lineSpacingCompact
            case .book: OwnerCopy.lineSpacingBook
            case .airy: OwnerCopy.lineSpacingAiry
            }
        }
    }

    enum Face: String, CaseIterable, Identifiable {
        case alegreya, system

        var id: Self { self }

        var title: String {
            switch self {
            case .alegreya: "Alegreya"
            case .system: "SF Pro"
            }
        }
    }
}
