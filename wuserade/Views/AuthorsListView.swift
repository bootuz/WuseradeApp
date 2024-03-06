//
//  AuthorsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI

struct AuthorsListView: View {
    @State private var viewModel = AuthorsViewModel(service: AuthorsService(httpClient: URLSession.shared))

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.groupedAndSortedAuthors, id: \.key) { group in
                    Section(header: Text(group.key.capitalized)) {
                        ForEach(group.value, id: \.name) { author in
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
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .refreshable {
                Task {
                    await viewModel.fetchAllAuthors()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleView(title: "усакlуэхэр")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.plain)
            .task {
                if viewModel.authors.isEmpty {
                    await viewModel.fetchAllAuthors()
                }
            }
            .analyticsScreen(name: "AuthorsListView")
        }
    }
}

#Preview {
    AuthorsListView()
}
