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
    /// The Firebase account: a silent anonymous one on launch, upgraded by linking Apple or Google.
    @State private var account = AccountManager(
        auth: FirebaseAuthBackend(),
        likes: FirestoreLikesStore(),
        pending: PendingLikesStore()
    )
    /// The likes of the current account.
    @State private var likes = LikesController(store: FirestoreLikesStore())

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

    /// Uploads the likes this device kept in SwiftData before likes moved to Firestore.
    private var migrator: LegacyLikesMigrator {
        LegacyLikesMigrator(container: sharedModelContainer, store: FirestoreLikesStore(), defaults: .standard)
    }

    /// The tests run inside the app. They must not sign in to, or write to, the real Firebase project.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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
                .environment(account)
                .environment(likes)
                // Launch: sign in anonymously (or keep the existing account), show its likes, and upload the
                // likes this device kept before accounts existed.
                .task {
                    guard !Self.isRunningTests else { return }
                    await account.start()
                    likes.bind(uid: account.state.uid)
                    if let uid = account.state.uid {
                        await migrator.migrateIfNeeded(uid: uid)
                    }
                }
                // Sign-in, sign-out and account deletion change the uid. Likes always follow the current account,
                // and an account that could not be created at launch (offline) is migrated once it exists.
                .onChange(of: account.state.uid) { _, uid in
                    likes.bind(uid: uid)
                    guard let uid else { return }
                    Task { await migrator.migrateIfNeeded(uid: uid) }
                }
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
