//
//  ContentView.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import SwiftData
import FirebaseAnalytics
import SFSafeSymbols

struct MainView: View {
    @State private var categoriesViewModel = PoemCategoriesViewModel(service: PoemCategoriesService(httpClient: URLSession.shared))
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
                    PoemCategoriesListView(viewModel: categoriesViewModel)
                        .tag(Tab.categories)
                })
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleView(title: "усэхэр")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    PresenterButton {
                        SearchView()
                    } label: {
                        Image(systemSymbol: SFSymbol.magnifyingglass)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    PresenterButton {
                        SettingsView()
                    } label: {
                        Image(systemSymbol: SFSymbol.gearshape)
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
