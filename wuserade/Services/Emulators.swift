// Minimum iOS 17.
//  Debug builds only: the `-useEmulators` launch argument runs the app against the local Firebase emulators
//  (project demo-wuserade) instead of production, for checking the daily discovery end to end. Release builds
//  have no such switch, and without the argument a debug build talks to production as before.

#if DEBUG
import FirebaseAnalytics
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

enum Emulators {
    static let argument = "-useEmulators"
    /// The project the emulators run as (`--project demo-wuserade`); their data is kept per project.
    static let projectID = "demo-wuserade"
    /// The simulator reaches the Mac's localhost directly. The ports are those of `firebase/firebase.test.json`.
    static let host = "localhost"
    static let authPort = 9099
    static let firestorePort = 8085
    static let functionsPort = 5001
    static let storagePort = 9199

    /// Whether this launch asked for the emulators. Off unless the argument is given.
    static func isRequested(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(argument)
    }

    /// Stands in for `FirebaseApp.configure()`, before anything uses Firebase. Analytics is switched off for this
    /// install, which persists until a launch without the argument switches it back on.
    static func configure() {
        guard let options = FirebaseOptions.defaultOptions() else {
            fatalError("GoogleService-Info.plist is missing")
        }
        options.projectID = projectID
        FirebaseApp.configure(options: options)
        Analytics.setAnalyticsCollectionEnabled(false)

        Auth.auth().useEmulator(withHost: host, port: authPort)
        // A user kept from production, or from an emulator run since stopped, is unknown to these emulators.
        try? Auth.auth().signOut()

        let settings = Firestore.firestore().settings
        settings.host = "\(host):\(firestorePort)"
        settings.isSSLEnabled = false
        // Nothing cached from production, or from an earlier emulator run, shows up.
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings

        Functions.functions(region: "europe-west3").useEmulator(withHost: host, port: functionsPort)
        Storage.storage().useEmulator(withHost: host, port: storagePort)
    }

    /// An empty catalog cache for this emulator run, apart from production's. Emptied at every emulator launch,
    /// since the emulators may hold other content than last time.
    static func freshCatalogCache() -> CatalogCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("emulators", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return CatalogCache(directory: directory)
    }
}
#endif
