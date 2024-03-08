//
//  AuthorView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI

struct AuthorView: View {
    @State private var viewModel = AuthorsViewModel(service: AuthorsService(httpClient: URLSession.shared))
    @State private var showSwipeView: Bool = false
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
                let name = author.name
                    .replacingOccurrences(of: "Ӏ", with: "I")
                    .replacingOccurrences(of: "ӏ", with: "l")
                TitleView(title: name)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showSwipeView.toggle()
                }, label: {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
                })
                .fullScreenCover(isPresented: $showSwipeView, content: {
                    PoemSwipeView(poems: viewModel.poems)
                })
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
            .environmentObject(FontSettingsManager())
            .tint(.primary)
    }
}
