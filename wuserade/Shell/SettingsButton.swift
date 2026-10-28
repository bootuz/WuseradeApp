// Minimum iOS 17.
//  The gearshape, ГъэпсыпӀэ: on the trailing side of every compact tab root, and in the regular-width sidebar.

import SwiftUI

struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Label("ГъэпсыпӀэ", systemImage: "gearshape")
        }
    }
}
