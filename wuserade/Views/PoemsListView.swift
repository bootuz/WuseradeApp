//
//  ContentView.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import SwiftData
import WebKit

struct PoemsListView: View {
    @State private var viewModel = PoemsViewModel(service: PoemsService(httpClient: URLSession.shared))
    @State private var query: String = ""
    @State private var showSearchView: Bool = false
    @State private var showSettingsView: Bool = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.allPoems) { poem in
                    NavigationLink {
                        PoemView(viewModel: PoemViewModel(poem: poem))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(poem.title)
                                .lineLimit(0)
                            Text(poem.author.name)
                                .foregroundStyle(.secondary)
                                .italic()
                                .fontDesign(.serif)
                        }
                    }
                    .task {
                        await viewModel.fetchMorePoemsIfNeeded(poem: poem)
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .listStyle(.plain)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("усэхэр")
                        .font(.custom("MarckScript-Regular", size: 25))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearchView.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .sheet(isPresented: $showSearchView, content: {
                        SearchView()
                    })
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettingsView.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .sheet(isPresented: $showSettingsView, content: {
                        SettingsView()
                    })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.allPoems.isEmpty {
                    await viewModel.fetchPoems()
                }
            }
        }
    }

    @ViewBuilder
    private func HeaderView() -> some View {
        HStack {
            Text("Усэщlэхэр")
                .font(.subheadline)
                .fontWeight(.bold)
            Spacer()
            Button(action: {

            }, label: {
                Text("Усу хъуар")
            })
        }
    }

}

#Preview {
    PoemsListView()
}
