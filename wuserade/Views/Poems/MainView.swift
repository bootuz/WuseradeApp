//
//  ContentView.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import FirebaseAnalytics
import SFSafeSymbols

struct MainView: View {
    @State private var categoriesViewModel = CategoriesViewModel(service: CategoriesService(httpClient: URLSession.shared))
    @State private var selectedTab: Tab = .poems

    enum Tab {
        case poems
        case categories

        var title: String {
            switch self {
                case .poems:
                    return "Усэщlэхэр"
                case .categories:
                    return "Зытеухуар"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker(selection: $selectedTab, content: {
                    Text(Tab.poems.title).tag(Tab.poems)
                    Text(Tab.categories.title).tag(Tab.categories)
                }) { }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                TabView(selection: $selectedTab,
                        content:  {
                    PoemsListView()
                        .tag(Tab.poems)
                    CategoriesView(viewModel: categoriesViewModel)
                        .tag(Tab.categories)
                })
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .animation(.easeInOut, value: selectedTab)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PresenterButton(presentationType: .sheet, destination: { SettingsView() }) {
                        Image(systemSymbol: SFSymbol.gearshape)
                    }
                }

                ToolbarItem(placement: .principal) {
                    TitleView(title: "усэхэр")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    PresenterButton(presentationType: .sheet, destination: { SearchView() }) {
                        Image(systemSymbol: SFSymbol.magnifyingglass)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    MainView()
        .environmentObject(FontSettingsManager())
        .modelContainer(for: PersistedPoem.self, inMemory: true)
        .tint(.primary)
}
