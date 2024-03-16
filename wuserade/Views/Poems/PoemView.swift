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
    @Environment(\.requestReview) var requestReview
    @State private var viewModel = PoemViewModel(service: PoemsService(httpClient: URLSession.shared))
    @State private var toast: Toast? = nil

    private var poemID: Int

    init(poemID: Int) {
        self.poemID = poemID
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
            } else {
                ProgressView()
            }
        }
        .task {
            await viewModel.fetchPoem(by: poemID)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }
}



#Preview {
    NavigationStack {
        PoemView(poemID: 203)
            .tint(.primary)
            .environmentObject(FontSettingsManager())
            .modelContainer(for: PersistedPoem.self, inMemory: true)
    }
}
