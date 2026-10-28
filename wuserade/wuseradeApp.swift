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
import GoogleSignIn

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
    /// The poem catalog, authors and themes every list reads. Starts from the on-disk cache.
    @State private var catalogStore: CatalogStore
    /// What the screens read: lists from the catalog, whole poems from Firestore, and the day's poem.
    @State private var library: Library
    /// The Firebase account: a silent anonymous one on launch, upgraded by linking Apple or Google.
    @State private var account = AccountManager(
        auth: FirebaseAuthBackend(),
        likes: FirestoreLikesStore(),
        pending: PendingLikesStore()
    )
    /// The likes of the current account.
    @State private var likes = LikesController(store: FirestoreLikesStore())

    init() {
        NavigationBarStyle.apply()
        let store = CatalogStore(repository: FirestoreContentRepository(), cache: .default)
        _catalogStore = State(initialValue: store)
        _library = State(initialValue: Library(store: store))
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

    /// Uploads the likes this device kept in SwiftData before likes moved to Firestore.
    private var migrator: LegacyLikesMigrator {
        LegacyLikesMigrator(container: sharedModelContainer, store: FirestoreLikesStore(), defaults: .standard)
    }

    /// The tests run inside the app. They must not sign in to, or write to, the real Firebase project.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// True when `meta/content.minimumAppVersion` is above this build. Stays false until `meta/content` has been
    /// read once, so a first launch offline never shows the update screen.
    private var isUpdateRequired: Bool {
        !AppVersion.isSupported(current: AppVersion.current, minimum: catalogStore.minimumAppVersion)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalogStore)
                .environment(library)
                .environment(account)
                .environment(likes)
                .sheet(isPresented: $firstLaunch) {
                    OnboardingView()
                }
                // Too old to work with the current content: nothing else is usable until the app is updated.
                .fullScreenCover(isPresented: .constant(isUpdateRequired)) {
                    UpdateRequiredView()
                }
                // Brings Google sign-in back into the app after the browser or account sheet.
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
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
                // Launch refresh, then the day's poem from the fresh catalog. It runs even if the scene is held
                // inactive at launch (e.g. by a permission alert).
                .task {
                    await catalogStore.refresh()
                    await library.loadDaysPoem()
                }
                // Every return to the foreground. On a cold start the first activation lands while the launch
                // refresh is still running, and `refresh()` ignores calls while one is running.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await catalogStore.refresh()
                        // The day may have turned while the app was in the background.
                        await library.loadDaysPoem()
                    }
                    // An account that could not be created earlier (offline) is tried again, so liking starts working
                    // without a relaunch. Skipped while an account operation is running, such as the launch one:
                    // that one is already creating it. The uid `onChange` above then binds and migrates the likes.
                    guard !Self.isRunningTests, account.state.uid == nil, !account.isBusy else { return }
                    Task { await account.start() }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
