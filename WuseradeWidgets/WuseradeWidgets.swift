// Minimum iOS 17.
//  The widget extension: the day's poem (medium), a short poem or the day's poem (small), and the lock screen.

import SwiftUI
import WidgetKit

@main
struct WuseradeWidgets: WidgetBundle {
    var body: some Widget {
        DaysPoemWidget()
        SmallPoemWidget()
        LockPoemWidget()
    }
}
