//
//  WuseradeApp.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }


    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcm = Messaging.messaging().fcmToken {
            print("fcm", fcm)
        }
    }
}

@main
struct wuseradeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("firstLaunch") private var firstLaunch = true
    @StateObject private var fontSettingsManager = FontSettingsManager()
    @StateObject private var notificationManager = NotificationManager()
    /// The poem catalog, authors and themes every list reads. Starts from the on-disk cache.
    @State private var catalogStore = CatalogStore(repository: FirestoreContentRepository(), cache: .default)

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
            TabBarView(notificationManager: notificationManager)
                .environmentObject(fontSettingsManager)
                .tint(.primary)
                .sheet(isPresented: $firstLaunch, onDismiss: {
                    Task {
                        await notificationManager.request()
                    }
                }, content: {
                    OnboardingView()
                        .interactiveDismissDisabled()
                })
                .environment(catalogStore)
                // Launch refresh. It runs even if the scene is held inactive at launch (e.g. by a permission alert).
                .task { await catalogStore.refresh() }
                // Every return to the foreground. On a cold start the first activation lands while the launch
                // refresh is still running, and `refresh()` ignores calls while one is running.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await catalogStore.refresh() }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
