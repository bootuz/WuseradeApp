//
//  PoemRow.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct PoemRow: View {
    let poemID: Int
    let title: String
    let authorName: String
    let preloaded: Poem?

    init(poemID: Int, title: String, authorName: String, preloaded: Poem? = nil) {
        self.poemID = poemID
        self.title = title
        self.authorName = authorName
        self.preloaded = preloaded
    }

    var body: some View {
        NavigationLink {
            PoemView(poemID: poemID, preloaded: preloaded)
        } label: {
            PoemLabel(title: title, authorName: authorName)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PoemRow(poemID: Poem.example.id, title: Poem.example.title, authorName: Poem.example.author.name)
    }
    .environmentObject(FontSettingsManager())
    .environment(CatalogStore.preview())
    .tint(.primary)
}
#endif
