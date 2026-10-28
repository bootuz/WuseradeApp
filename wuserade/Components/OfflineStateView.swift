// Minimum iOS 17.
//  No connection and nothing cached: wifi.slash, Мэхь мэхь, Интернетыр къэпщытэж, and Аргуэру with its spinner
//  inside the button while it retries. Never shown over cached content.

import SwiftUI

struct OfflineStateView: View {
    var retry: () async -> Void

    @State private var retrying = false

    var body: some View {
        EmptyStateView(title: String(localized: "Мэхь мэхь"), message: String(localized: "Интернетыр къэпщытэж"), systemImage: "wifi.slash") {
            Button {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            } label: {
                ZStack {
                    Text("Аргуэру").opacity(retrying ? 0 : 1)
                    if retrying {
                        ProgressView().tint(Palette.onAccent)
                    }
                }
            }
            .buttonStyle(.primaryCapsule)
            .disabled(retrying)
        }
    }
}
