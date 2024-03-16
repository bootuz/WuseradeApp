//
//  SearchView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct SearchView: View {
    @State private var viewModel = SearchViewModel(service: PoemsService(httpClient: URLSession.shared))
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.poems.isEmpty {
                    ContentUnavailableView {
                        Label("", systemSymbol: SFSymbol.magnifyingglass)
                    } description: {
                        Text("Узылъыхъуэ усэр мыбдеж къридзэнущ")
                            .padding(.top, -15)
                    }
                } else {
                    List {
                        ForEach(viewModel.poems) { poem in
                            NavigationLink {
                                PoemView(poemID: poem.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(poem.title)
                                    Text(poem.author.name)
                                }
                            }
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
        }
        .onSubmit(of: .search) {
            Task {
                await viewModel.searchPoems(query: viewModel.query)
            }
            AnalyticsManager.shared.logEvent(name: "search", params: ["query": viewModel.query])
        }
    }
}

#Preview {
    SearchView()
}
