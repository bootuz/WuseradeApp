import SwiftUI
import SFSafeSymbols

/// The empty state shown when content could not be loaded, with a button that tries again.
struct LoadFailedView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Мэхь мэхь", systemSymbol: SFSymbol.wifiSlash)
        } description: {
            // TODO(owner): copy. Meaning: "Couldn't load the poems. Check your internet connection."
            Text("Интернетыр къэпщытэж")
        } actions: {
            Button {
                retry()
            } label: {
                // TODO(owner): copy. Meaning: "Try again".
                Text("Аргуэру")
            }
        }
    }
}

#if DEBUG
#Preview {
    LoadFailedView(retry: {})
}
#endif
