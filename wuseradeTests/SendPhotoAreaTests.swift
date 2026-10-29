import FirebaseAuth
import Observation
import SwiftUI
import Testing
@testable import Wuserade

/// The area is hidden for a signed-in reader until the waiting record is checked, so the check has to start from a
/// hidden area. Each test hosts the area inside a parent stack, a scroll view and a list row, as the poet page does,
/// never as the root of a hosting controller: the root is the one place where an empty view still gets its task.
@MainActor
@Suite(.serialized)
final class SendPhotoAreaTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SendPhotoAreaTests-\(UUID().uuidString)", isDirectory: true)
    private let suiteName = "SendPhotoAreaTests-\(UUID().uuidString)"
    private var windows: [UIWindow] = []

    isolated deinit {
        windows.forEach { $0.isHidden = true }
        windows = []
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: Fixtures

    enum Container: String, CaseIterable {
        case stack, scrollView, listRow, poetHeaderInListRow
    }

    @Observable
    final class Model {
        var poetID = 7
        var hasPhoto = false
    }

    private struct AreaProbe: View {
        let model: Model

        var body: some View {
            SendPhotoArea(poet: Author(id: model.poetID, name: "Author \(model.poetID)"), hasPhoto: model.hasPhoto)
        }
    }

    private struct Env {
        let account: AccountManager
        let photos: PhotoSubmissions
        let store: FakePhotoSubmissionStore
        let library: Library
    }

    /// An account that has started, bound to photo submissions the way `wuseradeApp` binds it.
    private func makeEnv(user: AuthUserInfo?) async throws -> Env {
        let log = CallLog()
        let auth = FakeAuthBackend(currentUser: user, log: log)
        let account = AccountManager(
            auth: auth,
            likes: FakeLikesStore(log: log, ownerUid: { [auth] in auth.currentUser?.uid }),
            pending: PendingLikesStore(defaults: try #require(UserDefaults(suiteName: suiteName))),
            deleteWaitingPhotos: { _ in },
            setAnalyticsUserID: { _ in }
        )
        await account.start()
        let store = FakePhotoSubmissionStore()
        let photos = PhotoSubmissions(store: store, poetIDs: { [7, 8] })
        photos.bind(uid: PhotoSubmissions.uid(for: account.state))
        let repository = FakeContentRepository(
            meta: ContentMeta(
                catalogVersion: 1,
                catalogChunks: 1,
                authors: [AuthorEntry(id: 7, name: "Author 7", poemsCount: 3)],
                themes: [],
                nextPoemId: 100
            ),
            chunks: [CatalogChunk(version: 1, entries: [])]
        )
        let library = Library(store: CatalogStore(repository: repository, cache: CatalogCache(directory: directory)))
        return Env(account: account, photos: photos, store: store, library: library)
    }

    private func host(_ container: Container, env: Env, model: Model) throws {
        let area = AreaProbe(model: model)
        let root: AnyView
        switch container {
        case .stack:
            root = AnyView(VStack { Text("x"); area })
        case .scrollView:
            root = AnyView(ScrollView { VStack { Text("x"); area } })
        case .listRow:
            root = AnyView(List { VStack { Text("x"); area } })
        case .poetHeaderInListRow:
            root = AnyView(List { PoetHeader(poet: Author(id: model.poetID, name: "Author \(model.poetID)"), count: 3) })
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(
            rootView: root
                .environment(env.account)
                .environment(env.photos)
                .environment(env.library)
        )
        window.makeKeyAndVisible()
        windows.append(window)
    }

    private func appleCredential() -> ProviderCredential {
        ProviderCredential(
            provider: .apple,
            credential: OAuthProvider.appleCredential(withIDToken: "id", rawNonce: "nonce", fullName: nil),
            appleAuthorizationCode: "auth-code"
        )
    }

    /// Polls until `condition` holds, for at most two seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Tests

    @Test(arguments: Container.allCases)
    func `Signed in reader is checked while the area is still hidden`(container: Container) async throws {
        let env = try await makeEnv(user: AuthUserInfo(uid: "alice", isAnonymous: false, provider: .apple, email: nil))
        env.store.waiting = ["7_alice"]
        #expect(env.photos.status(poetID: 7) == .unchecked)

        try host(container, env: env, model: Model())
        try await waitUntil { env.photos.status(poetID: 7) != .unchecked }

        #expect(env.photos.status(poetID: 7) == .waiting, "\(container.rawValue)")
    }

    @Test(arguments: Container.allCases)
    func `Signing in while the area shows the button checks the new account`(container: Container) async throws {
        let env = try await makeEnv(user: nil)
        #expect(env.photos.uid == nil)
        try host(container, env: env, model: Model())
        try await Task.sleep(for: .milliseconds(200))
        #expect(env.store.calls == [], "\(container.rawValue): nothing to check before sign-in")

        // The sheet signs in: the state turns signed in first, which hides the area, and only then is the
        // new uid bound. The check for that uid still has to start.
        try await env.account.signIn(with: appleCredential())
        let uid = try #require(PhotoSubmissions.uid(for: env.account.state))
        env.store.waiting = ["7_\(uid)"]
        try await Task.sleep(for: .milliseconds(100))
        env.photos.bind(uid: uid)
        try await waitUntil { env.photos.status(poetID: 7) != .unchecked }

        #expect(env.photos.status(poetID: 7) == .waiting, "\(container.rawValue)")
    }

    @Test(arguments: [Container.stack, .scrollView, .listRow])
    func `A poet with a photo is not checked`(container: Container) async throws {
        let env = try await makeEnv(user: AuthUserInfo(uid: "alice", isAnonymous: false, provider: .apple, email: nil))
        let model = Model()
        model.hasPhoto = true

        try host(container, env: env, model: model)
        try await Task.sleep(for: .milliseconds(300))

        #expect(env.store.calls == [], "\(container.rawValue)")
    }

    @Test(arguments: [Container.stack, .scrollView, .listRow])
    func `A photo removed by a catalog refresh is checked`(container: Container) async throws {
        let env = try await makeEnv(user: AuthUserInfo(uid: "alice", isAnonymous: false, provider: .apple, email: nil))
        env.store.waiting = ["7_alice"]
        let model = Model()
        model.hasPhoto = true
        try host(container, env: env, model: model)
        try await Task.sleep(for: .milliseconds(300))
        #expect(env.store.calls == [], "\(container.rawValue): a poet with a photo is not checked")

        model.hasPhoto = false
        try await waitUntil { env.photos.status(poetID: 7) != .unchecked }

        #expect(env.photos.status(poetID: 7) == .waiting, "\(container.rawValue)")
    }

    @Test(arguments: [Container.stack, .scrollView, .listRow])
    func `The same area reused for another poet checks that poet`(container: Container) async throws {
        let env = try await makeEnv(user: AuthUserInfo(uid: "alice", isAnonymous: false, provider: .apple, email: nil))
        env.store.waiting = ["8_alice"]
        let model = Model()
        try host(container, env: env, model: model)
        try await waitUntil { env.photos.status(poetID: 7) != .unchecked }
        #expect(env.photos.status(poetID: 7) == .notWaiting, "\(container.rawValue)")

        model.poetID = 8
        try await waitUntil { env.photos.status(poetID: 8) != .unchecked }

        #expect(env.photos.status(poetID: 8) == .waiting, "\(container.rawValue)")
    }

    // The hosted area exposes no accessibility elements or UIKit controls, so the button is compared as pixels: the
    // label and a spinner swap places while the area is busy, which is the same state that disables the button.
    @Test func `The button is busy while a send for the poet is in flight`() async throws {
        let env = try await makeEnv(user: AuthUserInfo(uid: "alice", isAnonymous: false, provider: .apple, email: nil))
        env.store.sendDelay = .milliseconds(800)
        env.store.sendError = FakePhotoSubmissionStore.Failure()
        try host(.stack, env: env, model: Model())
        try await waitUntil { env.photos.status(poetID: 7) != .unchecked }
        try await Task.sleep(for: .milliseconds(300))
        let idle = try snapshot()

        // A send for another poet leaves this poet's button alone.
        let other = Task { try? await env.photos.send(Data([1]), for: 8) }
        try await waitUntil { env.photos.isSending(poetID: 8) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try snapshot() == idle, "a send for another poet does not busy the button")
        await other.value

        // The sheet can be closed while this poet's send runs; the button then shows the send, not "send a photo".
        let send = Task { try? await env.photos.send(Data([1]), for: 7) }
        try await waitUntil { env.photos.isSending(poetID: 7) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try snapshot() != idle, "the button is busy while the send runs")

        // The send fails, so the button is back for another try.
        await send.value
        try await Task.sleep(for: .milliseconds(300))
        #expect(try snapshot() == idle, "the button is back after a failed send")
    }

    private func snapshot() throws -> Data {
        let window = try #require(windows.last)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try #require(image.pngData())
    }
}
