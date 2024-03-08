//
//  PoemSwipeView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 06.03.2024.
//

import SwiftUI

struct PoemSwipeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fontManager: FontSettingsManager
    
    let poems: [Poem]

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(poems) { poem in
                        swipePoem(poem: poem)
                            .frame(maxWidth: .infinity)
                            .containerRelativeFrame(.horizontal, alignment: .center)
                    }
                }
            }
            .scrollTargetLayout()
            .scrollTargetBehavior(.paging)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Image(systemName: "xmark")
                    })
                }
            }
        }
    }

    private func swipePoem(poem: Poem) -> some View {
        ScrollView {
            VStack(alignment: .center) {
                PoemHeaderView(poem: poem)
                HStack {
                    PoemTextView(text: poem.content)
                    Spacer()
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

#Preview {
    PoemSwipeView(poems: [Poem.example, Poem.example])
        .environmentObject(FontSettingsManager())
        .modelContainer(for: [PersistedPoem.self], inMemory: true)
        .tint(.primary)
}
