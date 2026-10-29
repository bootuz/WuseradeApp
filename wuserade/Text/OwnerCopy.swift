// Minimum iOS 17.
//  Strings that do not exist yet. The owner or a native speaker writes each one before release;
//  never invent Kabardian. Replace the value in place and every screen picks it up.

import Foundation

enum OwnerCopy {
    static let daysPageLabel = "[owner copy: day’s page label]"
    static let poetOfTheDay = "[owner copy: poet of the day]"
    static let shortPoem = "[owner copy: a short poem]"
    static let allTheirPoems = "[owner copy: all their poems]"
    static let readOn = "[owner copy: read on]"
    static let moreBy = "[owner copy: more by]"
    static let youMightAlsoLike = "[owner copy: you might also like]"
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

    static let likeNeedsAccount = "[owner copy: liking waits until you have an account]"
    static let signedInWithApple = "[owner copy: signed in with Apple]"
    static let signedInWithGoogle = "[owner copy: signed in with Google]"
    static let signOutQuestion = "[owner copy: sign out?]"
    static let signOutMessage = "[owner copy: liked poems stay empty until you sign in again]"
    static let signOutFooter = "[owner copy: what signing out does]"
    static let deleteFooter = "[owner copy: what deleting the account removes]"
    static let deletesWaitingPhotos = "[owner copy: photos you sent that are still waiting are deleted too]"

    static let photoOfPoet = "[owner copy: photo of the poet]"
    static let reportPhoto = "[owner copy: report this photo]"
    static let reportSubject = "[owner copy: photo report]"
    static let sendPhoto = "[owner copy: send a photo]"
    static let photoWaiting = "[owner copy: photo sent, waiting for review]"
    static let signInToSendPhoto = "[owner copy: sign in to send a photo]"
    static let whySendingNeedsAccount = "[owner copy: why sending needs an account]"
    static let photoRights = "[owner copy: send only photos you have the right to share]"
    static let send = "[owner copy: send]"
    static let photoSendFailed = "[owner copy: photo could not be sent, try again]"
    static let photoSendBanned = "[owner copy: this account can't send photos]"

    static let morningPoem = "[owner copy: morning poem]"
    static let morningPoemTime = "[owner copy: time]"
    static let notificationsOff = "[owner copy: notifications are off for Wuserade in iOS Settings]"
    static let openSettings = "[owner copy: open Settings]"
    static let morningInvitation = "[owner copy: invitation to the morning poem]"
    static let turnOn = "[owner copy: turn on]"
    static let notNow = "[owner copy: not now]"

    /// The day's-page date read in words, such as '28 October'.
    static func dayAndMonth(_ date: Date) -> String {
        "[owner copy: day and month in words]"
    }

    /// The spoken position, such as '12 of 46'.
    static func position(_ index: Int, of total: Int) -> String {
        "[owner copy: \(index) of \(total)]"
    }
}
