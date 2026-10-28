//
//  SearchView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct SearchView: View {
    @Environment(CatalogStore.self) private var store
    @State private var viewModel = SearchViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Restarts the search when the query changes or a refresh brings a new catalog version.
    private struct SearchInput: Hashable {
        let query: String
        let catalogVersion: Int?
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if store.catalog == nil {
                    CatalogStatusView()
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView {
                        Label("", systemSymbol: SFSymbol.magnifyingglass)
                    } description: {
                        Text("Узылъыхъуэ усэр мыбдеж къридзэнущ")
                            .padding(.top, -15)
                    }
                } else {
                    List {
                        ForEach(viewModel.results) { poem in
                            PoemRow(poemID: poem.id, title: poem.title, authorName: poem.authorName)
                        }
                    }
                }
            }
            .analyticsScreen(name: "SearchView")
            .toolbar {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    ToolbarItem(placement: .topBarLeading) {
                        TitleView(title: "лъыхъуапlэ")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: {
                            dismiss()
                        }, label: {
                            Image(systemName: "xmark")
                        })
                    }
                    ToolbarItem(placement: .principal) {
                        TitleView(title: "лъыхъуапlэ")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: Text("Усэм е усакlуэм и цlэр"))
            .task(id: SearchInput(query: viewModel.query, catalogVersion: store.catalog?.version)) {
                await viewModel.search(in: store.catalog?.entries ?? [])
            }
        }
        .onSubmit(of: .search) {
            // Results already follow the typing; the event records queries the user committed to.
            AnalyticsManager.shared.logEvent(name: "search", params: ["query": viewModel.query])
        }
    }
}

#if DEBUG
#Preview {
    SearchView()
        .environment(CatalogStore.preview())
        .environmentObject(FontSettingsManager())
        .tint(.primary)
}
#endif
