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
            await viewModel.fetchPoemsOfAuthor(id: author.id)
        }
    }
}

#Preview {
    NavigationStack {
        AuthorView(author: Author(id: 1, name: "Усак1уэм и ц1эр"))
    }
}
