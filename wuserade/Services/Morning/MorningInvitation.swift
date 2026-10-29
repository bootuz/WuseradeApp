// Minimum iOS 17.
//  When Home shows the one-time invitation to the morning poem: from the reader's third distinct day, until they
//  answer it or turn the morning poem on.

import Foundation

enum MorningInvitation {
    static func shouldShow(visitDays: Int, done: Bool, enabled: Bool) -> Bool {
        visitDays >= 3 && !done && !enabled
    }
}
