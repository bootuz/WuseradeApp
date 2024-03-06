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
    @Environment(\.requestReview) var requestReview
    @EnvironmentObject private var fontManager: FontSettingsManager
    @Query private var poems: [PersistedPoem]

    @State var viewModel: PoemViewModel
    @State private var isLiked = false
    @State private var copyTapped = false
    @State private var shouldAnimate: Bool = false
    @State private var textViewheight: CGFloat = 0
    @State private var toast: Toast? = nil
    private let pastboard = UIPasteboard.general

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                PoemHeader()
                HStack {
                    PoemTextView(text: viewModel.poem.content)
                    Spacer()
                }
            }
            .padding()
        }
        .toastView(toast: $toast)
        .onAppear {
            if poemInFavourites() {
                shouldAnimate = false
                isLiked = true
            }
        }
        .onDisappear {
            requestReview()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    pastboard.string = "\(viewModel.poem.title)\n\(viewModel.poem.author.name)\n\n\(viewModel.poem.content)"
                    copyTapped.toggle()
                    showToast()
                }, label: {
                    Image(systemName: "doc.on.doc")
                })
                .sensoryFeedback(.success, trigger: copyTapped)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        shouldAnimate = true
                        isLiked.toggle()
                    }

                    if poemInFavourites() {
                        removePoemFromFavourites(poem: viewModel.poem)
                        AnalyticsManager.shared.logEvent(name: "poem", params: ["unlike": viewModel.poem.title])
                    } else {
                        addPoemToFavourites(poem: viewModel.poem)
                        AnalyticsManager.shared.logEvent(name: "poem", params: ["like": viewModel.poem.title])
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
                .sensoryFeedback(.impact(weight: .heavy, intensity: 5.0), trigger: isLiked)
            }
        }
        .analyticsScreen(name: "PoemView", extraParameters: ["poem" : viewModel.poem.title])
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
                HStack {
                    Text(viewModel.poem.author.name)
                        .font(.custom(fontManager.currentSettings.fontName, size: 18))
                        .italic()
                        .padding(.vertical, 1)
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                }
            }

            Divider()
                .padding(.top, 8)
        }
        .padding(.bottom, 10)
    }

    private func showToast() {
        withAnimation {
            toast = Toast(style: .copy, message: "Копие тепхащ", width: 160)
        }
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
