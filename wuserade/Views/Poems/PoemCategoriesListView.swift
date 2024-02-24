//
//  PoemCategoriesView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct PoemCategoriesListView: View {
    @State private var viewModel = PoemCategoriesViewModel(service: PoemCategoriesService(httpClient: URLSession.shared))

    var body: some View {
        List {
            ForEach(viewModel.categories) { category in
                NavigationLink {
                    PoemCategoryView(category: category)
                        .toolbarRole(.editor)
                } label: {
                    Text(category.title)
                }
            }
        }
        .listStyle(.plain)
        .task {
            if viewModel.categories.isEmpty {
                await viewModel.fetchCategories()
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }
}

struct PoemCategoryView: View {
    @State private var viewModel = PoemCategoriesViewModel(service: PoemCategoriesService(httpClient: URLSession.shared))
    let category: PoemCategory

    init(category: PoemCategory) {
        self.category = category
    }
    var body: some View {
        List {
            ForEach(viewModel.poems) { poem in
                NavigationLink {
                    PoemView(viewModel: PoemViewModel(poem: poem))
                } label: {
                    PoemLabel(poem: poem)
                }
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
                    Label("Мэхь мэхь", systemImage: "pencil.and.scribble")
                }, description: {
                    Text("Мы категорием усэ зэкlэ хэткъым")
                })
            }
        }
    }
}

#Preview {
    PoemCategoriesListView()
}

#Preview {
    PoemCategoryView(category: PoemCategory(id: 1, title: "Test"))
}
