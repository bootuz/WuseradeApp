//
//  AuthorView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI

struct AuthorView: View {
    @State private var viewModel = AuthorsViewModel(service: AuthorsService(httpClient: URLSession.shared))
    var author: Author

    init(author: Author) {
        self.author = author
    }

    var body: some View {
        List {
            ForEach(viewModel.poems) { poem in
                NavigationLink {
                    PoemView(viewModel: PoemViewModel(poem: poem))
                } label: {
                    VStack(alignment: .leading) {
                        Text(poem.title)
                            .lineLimit(0)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitleView(title: author.name)
            }
        }
        .listStyle(.plain)
        .task {
            if viewModel.poems.isEmpty {
                await viewModel.fetchPoemsOfAuthor(id: author.id)
            }
        }
        .analyticsScreen(name: "AuthorView", extraParameters: ["author" : author.name])
    }
}

#Preview {
    NavigationStack {
        AuthorView(author: Author(id: 1, name: "Усакlуэм и цlэр"))
            .navigationBarTitleDisplayMode(.inline)
    }
}
