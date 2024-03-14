//
//  PoemCategoriesView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct CategoriesView: View {
    @Bindable var viewModel: CategoriesViewModel<CategoriesService>

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
        .analyticsScreen(name: "PoemCategoriesListView")
    }
}

#Preview {
    NavigationStack {
        CategoriesView(viewModel: CategoriesViewModel(service: CategoriesService(httpClient: URLSession.shared)))
    }
}
