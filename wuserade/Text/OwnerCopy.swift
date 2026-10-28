// Minimum iOS 17.
//  Strings that do not exist yet. The owner or a native speaker writes each one before release;
//  never invent Kabardian. Replace the value in place and every screen picks it up.

import Foundation

enum OwnerCopy {
    static let daysPageLabel = "[owner copy: day’s page label]"
    static let readOn = "[owner copy: read on]"
    static let like = "[owner copy: like]"
    static let unlike = "[owner copy: unlike]"
    static let copy = "[owner copy: copy]"
    static let smaller = "[owner copy: smaller]"
    static let larger = "[owner copy: larger]"
    static let lineSpacing = "[owner copy: line spacing]"
    static let lineSpacingCompact = "[compact]"
    static let lineSpacingBook = "[book]"
    static let lineSpacingAiry = "[airy]"
    static let countNoun = "[owner copy: noun]"
    static let unknownAuthorHeader = "[owner copy: header]"
    static let recents = "[owner copy: recents]"
    static let clearRecents = "[owner copy: clear]"
    static let noResults = "[owner copy: no results]"
    static let likedEmptyBody = "[owner copy: how the heart in the reader works]"
    static let emptyTheme = "[owner copy: no poems in this theme yet]"
    static let emptyPoet = "[owner copy: no poems by this poet yet]"
    static let refreshFailed = "[owner copy: could not refresh; showing what was saved]"
    static let close = "[owner copy: close]"
    static let onboardingFirstLine = "[owner copy: replaces the weekly-poem promise]"
    static let acknowledgements = "[owner copy: acknowledgements: Alegreya, SIL Open Font License]"
    static let nothingSelected = "[owner copy: choose a poem]"

    static let unlikeSwipe = "[owner copy: unlike]"
    static let googleSignInConfirm = "[owner copy: Google sign-in wording]"

    /// The day's-page date read in words, such as '28 October'.
    static func dayAndMonth(_ date: Date) -> String {
        "[owner copy: day and month in words]"
    }

    /// The spoken position, such as '12 of 46'.
    static func position(_ index: Int, of total: Int) -> String {
        "[owner copy: \(index) of \(total)]"
    }
}
