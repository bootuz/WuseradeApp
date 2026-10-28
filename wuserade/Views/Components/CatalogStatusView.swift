import SwiftUI
import SFSafeSymbols

/// Stands in for a list while the catalog has not loaded: a spinner while a refresh is running or about to run,
/// and an empty state with a retry button once a refresh has failed (first launch offline, Review Focus 1).
/// Show it only while `CatalogStore.catalog` is nil.
struct CatalogStatusView: View {
    @Environment(CatalogStore.self) private var store

    var body: some View {
        if !store.isLoading, store.lastError != nil {
            ContentUnavailableView {
                Label("Мэхь мэхь", systemSymbol: SFSymbol.wifiSlash)
            } description: {
                // TODO(owner): copy. Meaning: "Couldn't load the poems. Check your internet connection."
                Text("Интернетыр къэпщытэж")
            } actions: {
                Button {
                    Task { await store.refresh() }
                } label: {
                    // TODO(owner): copy. Meaning: "Try again".
                    Text("Аргуэру")
                }
            }
        } else {
            ProgressView()
        }
    }
}

#if DEBUG
#Preview("Offline") {
    let store = CatalogStore.preview(loaded: false)
    CatalogStatusView()
        .environment(store)
        .task { await store.refresh() }
}

#Preview("Before first refresh") {
    CatalogStatusView()
        .environment(CatalogStore.preview(loaded: false))
}
#endif
