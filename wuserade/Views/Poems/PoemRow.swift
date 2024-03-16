//
//  PoemRow.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct PoemRow: View {
    var poem: Poem

    var body: some View {
        NavigationLink {
            PoemView(poemID: poem.id)
        } label: {
            PoemLabel(poem: poem)
        }
    }
}

#Preview {
    NavigationStack {
        PoemRow(poem: Poem.example)
    }
    .environmentObject(FontSettingsManager())
    .tint(.primary)
}
