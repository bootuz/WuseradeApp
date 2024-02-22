//
//  PoemView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import Pow
import SwiftData


struct PoemView: View {
    @Environment(\.modelContext) var context
    @EnvironmentObject private var fontManager: FontSettingsManager
    @Query private var poems: [PersistedPoem]
    @State var isLiked = false
    @State private var shouldAnimate: Bool = false
    @State private var textViewheight: CGFloat = 0
    @State var viewModel: PoemViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                PoemHeader()
                HStack {
                    SelectableTextView(text: viewModel.poem.content, height: $textViewheight)
                        .frame(height: textViewheight)
                    Spacer()
                }
            }
            .padding()
        }
        .onAppear {
            if poemInFavourites() {
                shouldAnimate = false
                isLiked = true
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        shouldAnimate = true
                        isLiked.toggle()
                    }

                    if poemInFavourites() {
                        removePoemFromFavourites(poem: viewModel.poem)
                    } else {
                        addPoemToFavourites(poem: viewModel.poem)
                    }
                } label: {
                    if isLiked {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .transition(shouldAnimate ? .movingParts.pop(.red) : .identity)
                    } else {
                        Image(systemName: "heart")
                            .foregroundStyle(.primary)
                            .transition(.identity)
                    }
                }
                .sensoryFeedback(.impact(flexibility: .solid), trigger: isLiked)
            }
        }
    }

    private func poemInFavourites() -> Bool {
        return poems.contains(where: { $0.poemID == viewModel.poem.id })
    }

    private func addPoemToFavourites(poem: Poem) {
        let persistedPoem: PersistedPoem = .toPersistedPoem(from: poem)
        context.insert(persistedPoem)
    }

    private func removePoemFromFavourites(poem: Poem) {
        guard let poemToDelete = poems.first(where: {$0.poemID == poem.id }) else { return }
        context.delete(poemToDelete)
    }

    private func PoemHeader() -> some View {
        VStack(alignment: .center) {
            Text(viewModel.poem.title)
                .font(.custom(fontManager.currentSettings.fontName, size: 30))
                .multilineTextAlignment(.center)
            NavigationLink {
                AuthorView(author: viewModel.poem.author)
            } label: {
                Text(viewModel.poem.author.name)
                    .font(.custom(fontManager.currentSettings.fontName, size: 18))
                    .italic()
                    .padding(.vertical, 1)
            }

            Divider()
        }
        .padding(.bottom, 10)
    }
}

#Preview {
    NavigationStack {
        PoemView(viewModel: PoemViewModel(poem: Poem.example))
            .tint(.primary)
            .modelContainer(for: PersistedPoem.self, inMemory: true)
            .environmentObject(FontSettingsManager())
    }
}
