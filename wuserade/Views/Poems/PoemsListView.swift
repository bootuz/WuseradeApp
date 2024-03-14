//
//  PoemsListView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct PoemsListView: View {
    @State var viewModel: PoemsViewModel = PoemsViewModel(service: PoemsService(httpClient: URLSession.shared))
    
    var body: some View {
        List {
            ForEach(viewModel.poems) { poem in
                PoemRow(poem: poem)
                .task {
                    await viewModel.fetchMorePoemsIfNeeded(poem: poem)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            Task {
                await viewModel.refreshPoems()
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task {
            if viewModel.poems.isEmpty {
                await viewModel.AllPoems()
            }
        }
        .analyticsScreen(name: "PoemsListView")
    }
}

#Preview {
    NavigationStack {
        PoemsListView()
    }
    .environmentObject(FontSettingsManager())
    .modelContainer(for: [PersistedPoem.self], inMemory: true)
    .tint(.primary)
}
