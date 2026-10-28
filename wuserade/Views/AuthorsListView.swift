//
//  AuthorsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI

struct AuthorsListView: View {
    @Environment(CatalogStore.self) private var store
    @State private var viewModel = AuthorsViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.grouped(store.authors), id: \.key) { group in
                    Section(header: Text(group.key.capitalized)) {
                        ForEach(group.value) { author in
                            NavigationLink(destination: {
                                AuthorView(author: author)
                            }, label: {
                                Text(author.name)
                            })
                        }
                    }
                }
            }
            .overlay {
                if store.catalog == nil {
                    CatalogStatusView()
                }
            }
            .refreshable {
                await store.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleView(title: "усакlуэхэр")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.plain)
            .analyticsScreen(name: "AuthorsListView")
        }
    }
}

#if DEBUG
#Preview {
    AuthorsListView()
        .environment(CatalogStore.preview())
}
#endif
