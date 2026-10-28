//
//  AuthorView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct AuthorView: View {
    @Environment(CatalogStore.self) private var store
    let author: Author

    init(author: Author) {
        self.author = author
    }

    var body: some View {
        let poems = store.catalog?.poems(byAuthor: author.id) ?? []
        List {
            ForEach(poems) { poem in
                // Title only: every poem on this screen is by the same author.
                NavigationLink {
                    PoemView(poemID: poem.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(poem.title)
                            .lineLimit(0)
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
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .principal) {
                let name = author.name
                    .replacingOccurrences(of: "Ӏ", with: "I")
                    .replacingOccurrences(of: "ӏ", with: "l")
                TitleView(title: name)
            }
        }
        .listStyle(.plain)
        .analyticsScreen(name: "AuthorView", extraParameters: ["author" : author.name])
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AuthorView(author: PreviewContent.authors[0].author)
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(CatalogStore.preview())
    .environmentObject(FontSettingsManager())
    .modelContainer(for: PersistedPoem.self, inMemory: true)
    .tint(.primary)
}
#endif
