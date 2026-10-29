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


    /// Hands the token to the app, which registers it for the morning poem.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        NotificationCenter.default.post(name: .fcmTokenDidChange, object: nil, userInfo: fcmToken.map { ["token": $0] })
    }
}

extension Notification.Name {
    /// Posted by `AppDelegate` with the new FCM token under "token", or no user info when there is none.
    static let fcmTokenDidChange = Notification.Name("fcmTokenDidChange")
}

@main
struct wuseradeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("firstLaunch") private var firstLaunch = true
    /// The poem catalog, authors and themes every list reads. Starts from the on-disk cache.
    @State private var catalogStore: CatalogStore
    /// What the screens read: lists from the catalog, whole poems from Firestore, and the day's picks.
    @State private var library: Library
    /// The Firebase account: a silent anonymous one on launch, upgraded by linking Apple or Google.
    @State private var account: AccountManager
    /// The likes of the current account.
    @State private var likes = LikesController(store: FirestoreLikesStore())
    /// The reading history of the current account, which the server's suggestions skip.
    @State private var reads: ReadsController
    /// Decides when a poem in the reader counts as read, and writes it to `reads`.
    @State private var readTracker: ReadTracker
    /// The poet photos the signed-in reader has sent and that wait for the owner.
    @State private var photos: PhotoSubmissions
    /// What the reader offers once a poem ends.
    private let keepReading: any KeepReadingService
    /// The morning poem setting, and this device's registration under the current account.
    @State private var morning: MorningPoemController

    init() {
        AppLanguage.applyDefault()
        NavigationBarStyle.apply()
        // The day's poem used to be picked on the device and kept here; it now comes from `daily/{date}`.
        UserDefaults.standard.removeObject(forKey: "daysPoem.day")
        UserDefaults.standard.removeObject(forKey: "daysPoem.poem")
        let store = CatalogStore(repository: FirestoreContentRepository(), cache: .default)
        _catalogStore = State(initialValue: store)
        #if DEBUG
        // `-previewDaily` runs the app over the in-memory preview content, with today's picks, for screenshots.
        let library = ProcessInfo.processInfo.arguments.contains("-previewDaily") ? Library.preview() : Library(store: store)
        // `-previewKeepReading` answers the end of every poem with made-up suggestions, for screenshots.
        keepReading = ProcessInfo.processInfo.arguments.contains("-previewKeepReading")
            ? PreviewKeepReadingService() : FirebaseKeepReadingService()
        #else
        let library = Library(store: store)
        keepReading = FirebaseKeepReadingService()
        #endif
        _library = State(initialValue: library)
        let photos = PhotoSubmissions(
            store: FirebasePhotoSubmissionStore(),
            poetIDs: { [library] in try await library.poetIDs() }
        )
        _photos = State(initialValue: photos)
        let installId = InstallID.current()
        let account = AccountManager(
            auth: FirebaseAuthBackend(),
            likes: FirestoreLikesStore(),
            pending: PendingLikesStore(),
            reads: FirestoreReadsStore(),
            pendingReads: PendingReadsStore(),
            knownReads: KnownReadsStore(),
            devices: FirestoreDeviceRegistry(),
            installId: installId,
            deleteWaitingPhotos: { [photos] uid in try await photos.deleteAll(uid: uid) }
        )
        _account = State(initialValue: account)
        // No read is written while a sign-in, sign-out or deletion runs: it could land on an account being merged
        // away or deleted.
        let reads = ReadsController(store: FirestoreReadsStore(), isPaused: { [account] in account.isBusy })
        _reads = State(initialValue: reads)
        _readTracker = State(initialValue: ReadTracker { [reads] in reads.markRead($0) })
        // Like reads, no registration is written while an account operation runs: it could land on an account being
        // left or deleted, and the server would keep sending to it. The account is reported again once it ends.
        #if DEBUG
        // `-previewMorningPoem` keeps the morning poem off Firestore, for screenshots. Pair it with
        // `-morningPoem.enabled YES` or `NO` to show either state without the permission prompt.
        let registry: any DeviceRegistry = ProcessInfo.processInfo.arguments.contains("-previewMorningPoem")
            ? PreviewDeviceRegistry() : FirestoreDeviceRegistry()
        #else
        let registry: any DeviceRegistry = FirestoreDeviceRegistry()
        #endif
        _morning = State(initialValue: MorningPoemController(
            registry: registry,
            permission: SystemNotificationPermission(),
            installId: installId,
            isPaused: { [account] in account.isBusy }
        ))
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
                .environment(photos)
                .environment(morning)
                .environment(\.readTracker, readTracker)
                .environment(\.keepReading, keepReading)
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
                    reads.bind(uid: account.state.uid)
                    // A token that arrived before the observer below was in place is picked up here. Fetching it can
                    // wait for the network, so nothing else waits for it.
                    Task {
                        if let token = try? await Messaging.messaging().token() {
                            await morning.tokenChanged(token)
                        }
                    }
                    await morning.accountChanged(uid: account.state.uid)
                    await morning.refreshPermission()
                    if let uid = account.state.uid {
                        await migrator.migrateIfNeeded(uid: uid)
                    }
                }
                // Sign-in, sign-out and account deletion change the uid. Likes and reads always follow the current
                // account, and an account that could not be created at launch (offline) is migrated once it exists.
                .onChange(of: account.state.uid) { _, uid in
                    likes.bind(uid: uid)
                    reads.bind(uid: uid)
                    guard let uid else { return }
                    Task { await migrator.migrateIfNeeded(uid: uid) }
                }
                // The morning poem registers nothing while an account operation runs; once it ends, the device is
                // registered under the resulting account (`AccountManager` removed it from the one it left).
                .onChange(of: account.isBusy) { _, isBusy in
                    guard !isBusy else { return }
                    Task { await morning.accountChanged(uid: account.state.uid) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .fcmTokenDidChange)) { note in
                    let token = note.userInfo?["token"] as? String
                    Task { await morning.tokenChanged(token) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    NSTimeZone.resetSystemTimeZone()
                    Task { await morning.timeZoneChanged() }
                }
                // Photos follow the signed-in (Apple or Google) account. The whole state is observed, not its uid:
                // linking an anonymous account keeps the uid, so a uid observer would miss the sign-in.
                .onChange(of: account.state, initial: true) {
                    photos.bind(uid: PhotoSubmissions.uid(for: account.state))
                }
                // Launch refresh, then today's picks. It runs even if the scene is held inactive at launch (e.g. by
                // a permission alert).
                .task {
                    await catalogStore.refresh()
                    await library.loadDaily()
                }
                // Every return to the foreground. On a cold start the first activation lands while the launch
                // refresh is still running, and `refresh()` ignores calls while one is running.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        // Notifications may have been allowed or blocked in iOS Settings meanwhile.
                        await morning.refreshPermission()
                        await morning.timeZoneChanged()
                    }
                    Task {
                        await catalogStore.refresh()
                        // The day may have turned while the app was in the background.
                        await library.loadDaily()
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
