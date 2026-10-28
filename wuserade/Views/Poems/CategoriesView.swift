//
//  PoemCategoriesView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct CategoriesView: View {
    @Environment(CatalogStore.self) private var store

    var body: some View {
        List {
            ForEach(store.themes) { category in
                NavigationLink {
                    PoemCategoryView(category: category)
                        .toolbarRole(.editor)
                } label: {
                    Text(category.title)
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
        .analyticsScreen(name: "PoemCategoriesListView")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CategoriesView()
    }
    .environment(CatalogStore.preview())
}
#endif
