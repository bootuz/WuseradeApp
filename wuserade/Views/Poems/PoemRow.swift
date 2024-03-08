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
            PoemView(viewModel: PoemViewModel(poem: poem))
        } label: {
            PoemLabel(poem: poem)
        }
    }
}

#Preview {
    PoemRow(poem: Poem.example)
}
