//
//  LikeButton.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI
import SwiftData
import Pow

struct LikeButton: View {
    @Environment(\.modelContext) var context
    @Query private var poems: [PersistedPoem]
    @State private var isLiked: Bool = false
    @State private var shouldAnimate: Bool = false

    var poem: Poem
    let onAnalyticsEvent: ((String, [String: String]) -> Void)?
    
    init(for poem: Poem, onAnalyticsEvent: ((String, [String : String]) -> Void)?) {
        self.poem = poem
        self.onAnalyticsEvent = onAnalyticsEvent
    }

    var body: some View {
        Button {
            withAnimation {
                shouldAnimate = true
                isLiked.toggle()
            }

            if isLiked {
                addPoemToFavourites(poem: poem)
                onAnalyticsEvent?("poem", ["unlike": poem.title])
            } else {
                removePoemFromFavourites(poem: poem)
                onAnalyticsEvent?("poem", ["like": poem.title])
            }
        } label: {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadToggleImage()
            } else {
                toggleImage()
            }
        }
        .buttonStyle(LikeButtonStyle())
        .onAppear {
            if poemIsLiked() {
                shouldAnimate = false
                isLiked = true
            }
        }
    }
    
    @ViewBuilder
    private func toggleImage() -> some View {
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

    @ViewBuilder
    private func iPadToggleImage() -> some View {
        if isLiked {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
        } else {
            Image(systemName: "heart")
                .foregroundStyle(.primary)
        }
    }

    private func poemIsLiked() -> Bool {
        return poems.contains(where: { $0.poemID == poem.id })
    }

    private func addPoemToFavourites(poem: Poem) {
        let persistedPoem: PersistedPoem = .toPersistedPoem(from: poem)
        context.insert(persistedPoem)
    }

    private func removePoemFromFavourites(poem: Poem) {
        guard let poemToDelete = poems.first(where: {$0.poemID == poem.id }) else { return }
        context.delete(poemToDelete)
    }
}

struct LikeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sensoryFeedback(.impact(weight: .heavy, intensity: 5.0), trigger: configuration.isPressed)
    }
}

#Preview {
    LikeButton(for: Poem.example, onAnalyticsEvent: AnalyticsManager.shared.logEvent)
        .modelContainer(for: PersistedPoem.self, inMemory: true)
        .font(.system(size: 60))

}
