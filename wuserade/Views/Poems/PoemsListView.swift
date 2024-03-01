//
//  ContentView.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import SwiftData
import FirebaseAnalytics

struct PoemsListView: View {
    @State private var viewModel = PoemsViewModel(service: PoemsService(httpClient: URLSession.shared))
    @State private var categoriesViewModel = PoemCategoriesViewModel(service: PoemCategoriesService(httpClient: URLSession.shared))
    @State private var showSearchView: Bool = false
    @State private var showSettingsView: Bool = false
    @State private var selected: Int = 0
    @AppStorage("colorScheme") private var colorScheme: Bool = false

    var body: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $selected) {
                    Text("Усэщlэхэр").tag(0)
                    Text("Зытеухуар").tag(1)
                }

                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                
                switch selected {
                    case 0:
                        ListView()
                            .transition(.move(edge: .leading))
                    case 1:
                        PoemCategoriesListView(viewModel: categoriesViewModel)
                            .transition(.move(edge: .trailing))
                    default:
                        EmptyView()
                }
            }
            .animation(.easeInOut, value: selected)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleView(title: "усэхэр")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearchView.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .sheet(isPresented: $showSearchView, content: {
                        SearchView()
                            .preferredColorScheme(colorScheme ? .dark : .light)
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
                            .preferredColorScheme(colorScheme ? .dark : .light)
                    })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.allPoems.isEmpty {
                    await viewModel.fetchPoems()
                }
            }
            .analyticsScreen(name: "PoemsListView")
        }
    }

    private func ListView() -> some View {
        List {
            ForEach(viewModel.allPoems) { poem in
                NavigationLink {
                    PoemView(viewModel: PoemViewModel(poem: poem))
                } label: {
                    PoemLabel(poem: poem)
                }
                .task {
                    await viewModel.fetchMorePoemsIfNeeded(poem: poem)
                }
            }
        }
        .refreshable {
            
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .listStyle(.plain)
    }
}



#Preview {
    PoemsListView()
        .tint(.primary)
}
