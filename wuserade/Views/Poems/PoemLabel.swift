//
//  PoemLabel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct PoemLabel: View {
    let title: String
    let authorName: String

    init(title: String, authorName: String) {
        self.title = title
        self.authorName = authorName
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .lineLimit(0)
            Text(authorName)
                .foregroundStyle(.secondary)
                .italic()
                .fontDesign(.serif)
        }
    }
}

#Preview {
    PoemLabel(title: Poem.example.title, authorName: Poem.example.author.name)
}
