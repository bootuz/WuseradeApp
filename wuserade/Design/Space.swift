// Minimum iOS 17.
//  Spacing and layout tokens, in points.

import CoreGraphics

enum Space {
    /// Row title to its subtitle.
    static let half: CGFloat = 2
    /// Title to author line; text to a trailing chevron.
    static let one: CGFloat = 4
    /// Lozenge to the day's label; empty-state title to body; header name to count line.
    static let two: CGFloat = 8
    /// Row vertical padding; the gap between stacked sign-in buttons.
    static let three: CGFloat = 12
    /// List and Form margins; empty-state lozenge to title.
    static let four: CGFloat = 16
    /// Between the day's-page actions; above a section label.
    static let six: CGFloat = 24
    /// Author line to the first verse line.
    static let eight: CGFloat = 32
    /// End lozenge to the next-poem rule; iPad reader top offset.
    static let twelve: CGFloat = 48
    /// Top offset of empty states and the Update cover; reader bottom padding.
    static let sixteen: CGFloat = 64

    /// The iPhone poem axis and the leading inset of content rows.
    static let readingMargin: CGFloat = 24
    /// Replaces `readingMargin` at accessibility text sizes.
    static let readingMarginAX: CGFloat = 16
    /// Side margin around the centred poem block in a regular-width detail of at least 600pt.
    static let detailMargin: CGFloat = 48
    /// The detail width at which `detailMargin` applies.
    static let detailTarget: CGFloat = 600
    /// Widest poem block, in ems of the verse size.
    static let measureMaxEm: CGFloat = 24
    /// Hanging indent of wrapped verse lines, in ems, capped at 25% of the measure.
    static let turnoverEm: CGFloat = 2
    /// One step of a poet's own indent, in ems; at most six steps.
    static let indentStepEm: CGFloat = 1
    /// Minimum hit area of every control.
    static let hitMin: CGFloat = 44
    /// Height of both sign-in buttons.
    static let signinHeight: CGFloat = 50
    /// iPad content-column width.
    static let columnContent: CGFloat = 320
}
