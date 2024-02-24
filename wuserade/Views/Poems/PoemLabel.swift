//
//  PoemLabel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct PoemLabel: View {
    var poem: Poem
    
    init(poem: Poem) {
        self.poem = poem
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(poem.title)
                .lineLimit(0)
            Text(poem.author.name)
                .foregroundStyle(.secondary)
                .italic()
                .fontDesign(.serif)
        }
    }
}

#Preview {
    PoemLabel(poem: Poem.example)
}
