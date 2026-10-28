//
//  LikedPoemsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct LikedPoemsView: View {
    @Environment(LikesController.self) private var likes

    var body: some View {
        NavigationStack {
            List {
                ForEach(likes.likes) { like in
                    // The like's own copy of the poem opens the screen, so it also works offline.
                    PoemRow(poemID: like.poemId, title: like.title, authorName: like.authorName, preloaded: like.poem)
                }
            }
            .toolbarRole(.editor)
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if likes.likes.isEmpty {
                    ContentUnavailableView(label: {
                        Label("Уигу ирихьа", systemSymbol: SFSymbol.heartFill)
                    }, description: {
                        Text("усэхэр мыбдеж къридзэнущ.")
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleView(title: "сигу ирихьахэр")
                }
            }
            .analyticsScreen(name: "LikedPoemsView")
        }
    }
}

#if DEBUG
#Preview {
    LikedPoemsView()
        .environment(LikesController.preview(likes: [Like(poem: Poem.example)]))
        .environment(CatalogStore.preview())
        .environmentObject(FontSettingsManager())
}
#endif
