// Minimum iOS 17.
//  The widgets' strings. Like `OwnerCopy`, the slots are written by the owner or a native speaker before
//  release; never invent Kabardian. The small widget's setting and its two choices are written in
//  `SmallPoemIntent` itself, because App Intents metadata takes only literals.

import Foundation

enum WidgetCopy {
    static let daysPageLabel = "[owner copy: day’s page label]"
    static let daysPoemName = "[owner copy: widget: day’s poem]"
    static let daysPoemDescription = "[owner copy: widget: day’s poem, description]"
    static let smallName = "[owner copy: widget: a short poem]"
    static let smallDescription = "[owner copy: widget: a short poem, description]"
    static let lockName = "[owner copy: widget: lock screen]"
    static let lockDescription = "[owner copy: widget: lock screen, description]"
    /// The wordmark, as the app writes it in Settings and on a shared poem.
    static let appName = "Усэрадэ"
}
