//
//  PoemHeaderView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct PoemHeaderView: View {
    @EnvironmentObject private var fontManager: FontSettingsManager
    let poem: Poem

    var body: some View {
        VStack(alignment: .center) {
            poemTitle
            NavigationLink {
                AuthorView(author: poem.author)
            } label: {
                authorName
            }

            Divider()
                .padding(.top, 8)
        }
        .padding(.bottom, 10)
    }

    var poemTitle: some View {
        Text(poem.title)
            .font(.custom(fontManager.currentSettings.fontName, size: 30))
            .multilineTextAlignment(.center)
    }

    var authorName: some View {
        HStack {
            Text(poem.author.name)
                .font(.custom(fontManager.currentSettings.fontName, size: 18))
                .italic()
                .padding(.vertical, 1)
            Image(systemName: "chevron.right")
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        PoemHeaderView(poem: Poem.example)
            .environmentObject(FontSettingsManager())
            .tint(.primary)
    }
}
