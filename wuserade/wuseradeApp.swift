//
//  WuseradeApp.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct wuseradeApp: App {
    @AppStorage("firstLaunch") private var firstLaunch = true
    @StateObject private var fontSettingsManager = FontSettingsManager()

    init() {
        FirebaseApp.configure()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PersistedPoem.self,
            PersistedAuthor.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TabBarView()
                .environmentObject(fontSettingsManager)
                .tint(.primary)
                .sheet(isPresented: $firstLaunch, content: {
                    OnboardingView()
                        .interactiveDismissDisabled()
                })
        }
        .modelContainer(sharedModelContainer)
    }
}
