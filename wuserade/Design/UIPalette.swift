// Minimum iOS 17.
//  The same colour tokens for UIKit code: the verse text view and the navigation bar appearance.

import UIKit

enum UIPalette {
    static let ink = UIColor(named: "ink") ?? .label
    static let inkSecondary = UIColor(named: "ink-secondary") ?? .secondaryLabel
    static let inkTertiary = UIColor(named: "ink-tertiary") ?? .tertiaryLabel
    static let gilt = UIColor(named: "gilt") ?? .label
}
