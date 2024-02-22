//
//  wuseradeApp.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import SwiftData

@main
struct wuseradeApp: App {
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

    @StateObject private var fontSettingsManager = FontSettingsManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(fontSettingsManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
