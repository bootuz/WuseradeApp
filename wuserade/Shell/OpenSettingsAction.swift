// Minimum iOS 17.
//  Presents the one Settings sheet, which the root view owns.

import SwiftUI

struct OpenSettingsAction {
    var handler: () -> Void = {}

    func callAsFunction() {
        handler()
    }
}

extension EnvironmentValues {
    @Entry var openSettings = OpenSettingsAction()
}
