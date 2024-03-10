//
//  MainView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import FirebaseAnalytics
import SFSafeSymbols

struct TabBarView: View {
    @ObservedObject var notificationManager: NotificationManager
    @AppStorage("colorScheme") private var colorScheme: Bool = false
    @AppStorage("firstLaunch") private var firstLaunch = true

    var body: some View {
        TabView {
            MainView().tabItem { Label("Усэхэр", systemSymbol: SFSymbol.pencilAndScribble) }.tag(1)
            AuthorsListView().tabItem { Label("Усакlуэхэр", systemSymbol: SFSymbol.person2) }.tag(2)
            LikedPoemsView().tabItem { Label("Сигу ирихьахэр", systemSymbol: SFSymbol.heart) }.tag(3)
        }
        .tint(.primary)
        .preferredColorScheme(colorScheme ? .dark : .light)
        .onAppear {
            if firstLaunch {
                Analytics.setUserID(UUID().uuidString)
            }
            
            if !firstLaunch {
                Task {
                    await notificationManager.request()
                }
            }
        }
    }
}

#Preview {
    TabBarView(notificationManager: NotificationManager())
        .environmentObject(FontSettingsManager())
        .modelContainer(for: PersistedPoem.self, inMemory: true)
}
