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

                TabView(selection: $selectedTab) {
                    PoemsListView()
                        .tag(Tab.poems)
                    CategoriesView()
                        .tag(Tab.categories)
                }
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

#if DEBUG
#Preview {
    MainView()
        .environment(CatalogStore.preview())
        .environmentObject(FontSettingsManager())
        .environment(LikesController.preview())
        .environment(AccountManager.preview())
        .tint(.primary)
}
#endif
