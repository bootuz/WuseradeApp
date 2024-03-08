//
//  PoemCategoriesView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct PoemCategoriesListView: View {
    @Bindable var viewModel: PoemCategoriesViewModel

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
        PoemCategoriesListView(viewModel: PoemCategoriesViewModel(service: PoemCategoriesService(httpClient: URLSession.shared)))
    }
}
