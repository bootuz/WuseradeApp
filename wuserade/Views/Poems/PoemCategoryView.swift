//
//  PoemCategoryView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 24.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct PoemCategoryView: View {
    @State private var viewModel = CategoriesViewModel(service: CategoriesService(httpClient: URLSession.shared))
    let category: Category

    init(category: Category) {
        self.category = category
    }
    var body: some View {
        List {
            ForEach(viewModel.poems) { poem in
                PoemRow(poem: poem)
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitleView(title: category.title)
            }
        }
        .task {
            if viewModel.poems.isEmpty {
                await viewModel.fetchPoemsByCategory(id: category.id)
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.poems.isEmpty {
                ContentUnavailableView(label: {
                    Label("Мэхь мэхь", systemSymbol: SFSymbol.pencilAndScribble)
                }, description: {
                    Text("Мы категорием усэ зэкlэ хэткъым")
                })
            }
        }
        .analyticsScreen(name: "PoemCategoryView", extraParameters: ["category" : category.title])
    }
}

#Preview {
    NavigationStack {
        PoemCategoryView(category: Category(id: 2, title: "Test"))
            .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(FontSettingsManager())
    .modelContainer(for: PersistedPoem.self, inMemory: true)
    .tint(.primary)
}
