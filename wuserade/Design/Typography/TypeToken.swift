// Minimum iOS 17.
//  The serif type tokens. Sizes are base sizes: `Font.custom(_:size:relativeTo:)` scales them with Dynamic Type.
//  `relativeTo` is given by the design system for wordmark, largeTitle, poemTitle and poemBody; the others
//  follow the nearest system text style.

import SwiftUI

enum TypeToken {
    case wordmark, largeTitle, headerTitle, dayTitle, emptyTitle
    case poemTitle, authorLine, poemBody, poemBodyWide, poemPartHead, dateline, runningHead, folio
    case rowTitle, rowFirstLine, rowName, rowSubtitle, rowMeta, indexLetter, sectionLabel, prose

    var face: SerifFace {
        switch self {
        case .wordmark, .largeTitle, .headerTitle, .dayTitle, .emptyTitle,
             .poemTitle, .poemPartHead, .runningHead, .rowTitle, .indexLetter, .sectionLabel:
            .medium
        case .authorLine, .dateline, .rowSubtitle:
            .italic
        case .poemBody, .poemBodyWide, .folio, .rowFirstLine, .rowName, .rowMeta, .prose:
            .regular
        }
    }

    var size: CGFloat {
        switch self {
        case .wordmark, .largeTitle: 34
        case .headerTitle: 28
        case .dayTitle: 26
        case .poemTitle: 24
        case .emptyTitle, .indexLetter: 22
        case .poemBodyWide: 21
        case .poemBody, .rowTitle, .rowFirstLine, .rowName: 19
        case .authorLine: 18
        case .poemPartHead, .runningHead, .prose: 17
        case .dateline, .rowSubtitle, .rowMeta: 16
        case .folio, .sectionLabel: 15
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .wordmark: 40
        case .largeTitle: 41
        case .headerTitle: 34
        case .dayTitle: 32
        case .poemTitle: 30
        case .emptyTitle, .indexLetter: 28
        case .poemBodyWide: 31
        case .poemBody, .poemPartHead: 28
        case .rowTitle, .rowFirstLine, .rowName, .authorLine, .prose: 24
        case .runningHead, .dateline: 22
        case .rowSubtitle, .rowMeta: 21
        case .folio, .sectionLabel: 20
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .wordmark, .largeTitle: .largeTitle
        case .headerTitle, .dayTitle: .title
        case .poemTitle, .emptyTitle, .indexLetter: .title2
        case .runningHead: .headline
        case .dateline, .rowSubtitle, .rowMeta: .callout
        case .folio, .sectionLabel: .subheadline
        case .authorLine, .poemBody, .poemBodyWide, .poemPartHead, .rowTitle, .rowFirstLine, .rowName, .prose: .body
        }
    }

    /// Tracking in ems of the scaled size.
    var trackingEm: CGFloat {
        switch self {
        case .wordmark: 0.01
        case .dayTitle, .poemTitle: 0.08
        case .poemPartHead: 0.1
        case .runningHead: 0.06
        case .folio: 0.02
        case .rowTitle: 0.05
        case .sectionLabel: 0.12
        default: 0
        }
    }

    /// All small caps: titles, labels and part heads. Names are never small caps.
    var smallCaps: Bool {
        switch self {
        case .dayTitle, .poemTitle, .poemPartHead, .runningHead, .rowTitle, .sectionLabel: true
        default: false
        }
    }

    /// Lining tabular figures for counts and the folio; verse keeps Alegreya's oldstyle default.
    var tabularFigures: Bool {
        self == .rowMeta || self == .folio
    }
}
