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

    init(poemID: Int, title: String, authorName: String) {
        self.poemID = poemID
        self.title = title
        self.authorName = authorName
    }

    var body: some View {
        NavigationLink {
            PoemView(poemID: poemID)
        } label: {
            PoemLabel(title: title, authorName: authorName)
        }
    }
}

#Preview {
    NavigationStack {
        PoemRow(poemID: Poem.example.id, title: Poem.example.title, authorName: Poem.example.author.name)
    }
    .environmentObject(FontSettingsManager())
    .tint(.primary)
}
