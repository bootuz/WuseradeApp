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
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var viewModel = PoemsViewModel(service: PoemsService(httpClient: URLSession.shared))
    @State private var query: String = ""
    @State private var showSearchView: Bool = false
    @State private var showSettingsView: Bool = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.allPoems) { poem in
                    NavigationLink {
                        PoemView(poem: poem)
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

                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .sheet(isPresented: $showSearchView, content: {
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

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    PoemsListView()
        .modelContainer(for: Item.self, inMemory: true)
}
