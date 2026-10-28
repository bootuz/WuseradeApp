//
//  PoemView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import StoreKit
import Pow
import SwiftData


/// Shows one poem. Pass `preloaded` when the caller already has the poem; otherwise it is read from Firestore.
struct PoemView: View {
    @Environment(CatalogStore.self) private var store

    let poemID: Int
    let preloaded: Poem?

    init(poemID: Int, preloaded: Poem? = nil) {
        self.poemID = poemID
        self.preloaded = preloaded
    }

    var body: some View {
        // The environment is not available in `init`, so the view model is built one level down,
        // where `@State` can take the repository as its initial value.
        PoemContentView(poemID: poemID, repository: store.repository, preloaded: preloaded)
    }
}

private struct PoemContentView: View {
    @Environment(\.requestReview) var requestReview
    @State private var viewModel: PoemViewModel
    @State private var toast: Toast? = nil

    private let poemID: Int

    init(poemID: Int, repository: ContentRepository, preloaded: Poem?) {
        self.poemID = poemID
        _viewModel = State(initialValue: PoemViewModel(repository: repository, preloaded: preloaded))
    }

    var body: some View {
        ZStack {
            if let poem = viewModel.poem {
                ScrollView {
                    VStack(alignment: .center) {
                        PoemHeaderView(poem: poem)
                        HStack {
                            PoemTextView(text: poem.content)
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
                .toastView(toast: $toast)
                .onDisappear {
                    Task {
                        requestReview()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CopyButton(for: poem, toast: $toast)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        LikeButton(for: poem, onAnalyticsEvent: AnalyticsManager.shared.logEvent)
                    }
                }
                .analyticsScreen(name: "PoemView", extraParameters: ["poem" : poem.title])
            } else if viewModel.loadFailed {
                LoadFailedView {
                    Task { await viewModel.load(id: poemID) }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await viewModel.load(id: poemID)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }
}



#if DEBUG
#Preview {
    NavigationStack {
        PoemView(poemID: 203)
            .tint(.primary)
            .environmentObject(FontSettingsManager())
            .modelContainer(for: PersistedPoem.self, inMemory: true)
    }
    .environment(CatalogStore.preview())
}

#Preview("Load failed") {
    NavigationStack {
        PoemView(poemID: 203)
            .tint(.primary)
            .environmentObject(FontSettingsManager())
            .modelContainer(for: PersistedPoem.self, inMemory: true)
    }
    .environment(CatalogStore.preview(loaded: false))
}
#endif
