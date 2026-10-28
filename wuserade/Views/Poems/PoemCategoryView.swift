//
//  PoemCategoryView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 24.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct PoemCategoryView: View {
    @Environment(CatalogStore.self) private var store
    let category: Category

    init(category: Category) {
        self.category = category
    }

    var body: some View {
        let poems = store.catalog?.poems(inTheme: category.id) ?? []
        List {
            ForEach(poems) { poem in
                PoemRow(poemID: poem.id, title: poem.title, authorName: poem.authorName)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await store.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitleView(title: category.title)
            }
        }
        .overlay {
            if store.catalog == nil {
                CatalogStatusView()
            } else if poems.isEmpty {
                ContentUnavailableView(label: {
                    Label("Мэхь мэхь", systemSymbol: SFSymbol.pencilAndScribble)
                }, description: {
                    Text("Мы категорием усэ зэкlэ хэткъым")
                })
            }
        }
        .analyticsScreen(name: "PoemCategoryView", extraParameters: ["category" : category.title])
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PoemCategoryView(category: PreviewContent.themes[0])
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(CatalogStore.preview())
    .environmentObject(FontSettingsManager())
    .environment(LikesController.preview())
    .environment(AccountManager.preview())
    .tint(.primary)
}
#endif
