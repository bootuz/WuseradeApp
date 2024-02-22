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
                ForEach(viewModel.authors) { author in
                    NavigationLink(destination: {
                        AuthorView(author: author)
                    }, label: {
                        Text(author.name)
                    })
                    .task {
                        if viewModel.hasReachedEnd(of: author) {
                            await viewModel.fetchNextAuthors()
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("усакlуэхэр")
                        .font(.custom("MarckScript-Regular", size: 25))
                }
            }
//            .navigationTitle("Усакlуэхэр")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.plain)
            .task {
                if viewModel.authors.isEmpty {
                    await viewModel.fetchAllAuthors()
                }
            }
        }
    }
}

#Preview {
    AuthorsListView()
}
