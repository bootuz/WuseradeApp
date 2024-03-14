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
    @State private var viewModel: PoemViewModel
    @State private var toast: Toast? = nil

    init(viewModel: PoemViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                PoemHeaderView(poem: viewModel.poem)
                HStack {
                    PoemTextView(text: viewModel.poem.content)
                    Spacer()
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CopyButton(for: viewModel.poem, toast: $toast)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                LikeButton(for: viewModel.poem, onAnalyticsEvent: AnalyticsManager.shared.logEvent)
            }
        }
        .analyticsScreen(name: "PoemView", extraParameters: ["poem" : viewModel.poem.title])
    }
}



#Preview {
    NavigationStack {
        PoemView(viewModel: PoemViewModel(poem: Poem.example))
            .tint(.primary)
            .environmentObject(FontSettingsManager())
            .modelContainer(for: PersistedPoem.self, inMemory: true)
    }
}
