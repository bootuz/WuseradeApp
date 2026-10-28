// Minimum iOS 17.
//  The bundled Alegreya cuts, with the face swap that Bold Text and the reader's bold switch make.

import Foundation

enum SerifFace {
    case regular, medium, italic

    /// One step heavier: Regular to Medium, Medium to Bold, Italic to Bold Italic.
    var heavier: SerifFace.Cut {
        switch self {
        case .regular: .medium
        case .medium: .bold
        case .italic: .boldItalic
        }
    }

    var cut: SerifFace.Cut {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .italic: .italic
        }
    }

    func cut(heavier: Bool) -> SerifFace.Cut {
        heavier ? self.heavier : cut
    }

    /// A PostScript name in the app bundle.
    enum Cut: String {
        case regular = "Alegreya-Regular"
        case medium = "Alegreya-Medium"
        case bold = "Alegreya-Bold"
        case italic = "Alegreya-Italic"
        case boldItalic = "Alegreya-BoldItalic"

        /// One step heavier, for matched search letters inside an already heavier style.
        var heavier: Cut {
            switch self {
            case .regular: .medium
            case .medium, .bold: .bold
            case .italic, .boldItalic: .boldItalic
            }
        }
    }
}
