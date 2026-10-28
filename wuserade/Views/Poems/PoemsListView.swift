//
//  PoemsListView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

/// The home list: the whole catalog, newest first, shown a page at a time.
struct PoemsListView: View {
    @Environment(CatalogStore.self) private var store
    @State private var viewModel = PoemsViewModel()

    var body: some View {
        let poems = store.catalog?.newestFirst() ?? []
        List {
            ForEach(viewModel.visible(poems)) { poem in
                PoemRow(poemID: poem.id, title: poem.title, authorName: poem.authorName)
                    .onAppear {
                        viewModel.loadMoreIfNeeded(current: poem, in: poems)
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await store.refresh()
        }
        .overlay {
            if store.catalog == nil {
                CatalogStatusView()
            }
        }
        .analyticsScreen(name: "PoemsListView")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PoemsListView()
    }
    .environment(CatalogStore.preview())
    .environmentObject(FontSettingsManager())
    .modelContainer(for: [PersistedPoem.self], inMemory: true)
    .tint(.primary)
}
#endif
