import Foundation
import Testing
import FirebaseAuth
@testable import Wuserade

@MainActor
final class AccountManagerTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own defaults suite.
    private let suiteName = "AccountManagerTests-\(UUID().uuidString)"
    private var analyticsUserIDs: [String] = []

    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_002_000)

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: Fixtures

    private struct Env {
        let manager: AccountManager
        let auth: FakeAuthBackend
        let likes: FakeLikesStore
        let pending: PendingLikesStore
        let photos: FakePhotoDeleter
        let log: CallLog
    }

    /// The likes fake enforces the security rules: only the signed-in uid can touch its data.
    private func makeEnv(currentUser: AuthUserInfo? = nil) throws -> Env {
        let log = CallLog()
        let auth = FakeAuthBackend(currentUser: currentUser, log: log)
        let likes = FakeLikesStore(log: log, ownerUid: { [auth] in auth.currentUser?.uid })
        let pending = PendingLikesStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let photos = FakePhotoDeleter(log: log)
        let manager = AccountManager(
            auth: auth,
            likes: likes,
            pending: pending,
            deleteWaitingPhotos: { try await photos.deleteAll(uid: $0) }
        ) { [weak self] uid in
            self?.analyticsUserIDs.append(uid)
        }
        return Env(manager: manager, auth: auth, likes: likes, pending: pending, photos: photos, log: log)
    }

    private func like(_ id: Int, at date: Date) -> Like {
        Like(
            poem: Poem(id: id, title: "Poem \(id)", author: Author(id: 1, name: "Author"), content: "Text \(id)"),
            likedAt: date
        )
    }

    private let appleUser = AuthUserInfo(uid: "apple-user", isAnonymous: false, provider: .apple, email: "a@example.com")
    private let googleUser = AuthUserInfo(uid: "google-user", isAnonymous: false, provider: .google, email: "g@example.com")

    private func appleCredential(code: String? = "auth-code") -> ProviderCredential {
        ProviderCredential(
            provider: .apple,
            credential: OAuthProvider.appleCredential(withIDToken: "id", rawNonce: "nonce", fullName: nil),
            appleAuthorizationCode: code
        )
    }

    private func googleCredential() -> ProviderCredential {
        ProviderCredential(
            provider: .google,
            credential: GoogleAuthProvider.credential(withIDToken: "id", accessToken: "access"),
            appleAuthorizationCode: nil
        )
    }

    // MARK: start

    @Test func `Start signs in anonymously once`() async throws {
        let env = try makeEnv()
        // Overlapping calls (e.g. launch plus a sign-out) must not create two anonymous accounts.
        env.auth.setAnonymousSignInDelay(.milliseconds(50))
        async let first: Void = env.manager.start()
        async let second: Void = env.manager.start()
        _ = await (first, second)
        await env.manager.start()

        #expect(env.auth.calls.filter { $0 == "signInAnonymously" }.count == 1)
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
        #expect(env.manager.state.uid == "anon-1")
        #expect(env.likes.userDocuments["anon-1"] != nil)
        #expect(analyticsUserIDs.last == "anon-1")
    }

    @Test func `Start keeps existing user`() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()

        #expect(!env.auth.calls.contains("signInAnonymously"))
        #expect(env.manager.state == .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))
        #expect(env.likes.calls == ["ensureUserDocument"])
        #expect(analyticsUserIDs == ["apple-user"])
    }

    @Test func `Start failure stays signed out and a later start retries`() async throws {
        let env = try makeEnv()
        env.auth.setAnonymousSignInError(FakeAuthBackend.Failure())
        await env.manager.start()

        #expect(env.manager.state == .signedOut)
        #expect(env.manager.state.uid == nil)
        #expect(env.likes.calls == [])
        #expect(analyticsUserIDs == [])

        env.auth.setAnonymousSignInError(nil)
        await env.manager.start()
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
    }

    // MARK: signIn

    @Test func `Link success keeps uid`() async throws {
        let env = try makeEnv()
        await env.manager.start()
        env.likes.resetCalls()

        try await env.manager.signIn(with: appleCredential())

        #expect(env.manager.state == .signedIn(uid: "anon-1", provider: .apple, email: "anon-1@example.com"))
        #expect(env.likes.calls == [])
    }

    @Test func `Credential in use merges anonymous likes`() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        env.likes.seed([like(1, at: t2)], uid: "google-user")
        await env.manager.start()
        env.likes.seed([like(1, at: t1), like(2, at: t3)], uid: "anon-1")
        env.log.reset()

        try await env.manager.signIn(with: googleCredential())

        #expect(env.manager.state == .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        #expect(env.likes.likes(for: "google-user") == [like(2, at: t3), like(1, at: t1)])
        // The anonymous account's data and user are gone.
        #expect(env.likes.likes(for: "anon-1") == [])
        #expect(env.likes.userDocuments["anon-1"] == nil)
        #expect(env.auth.deletedUids == ["anon-1"])
        #expect(env.pending.load() == [])
        // The anonymous data is read and deleted while still signed in as the anonymous user,
        // because the rules only let a user touch their own data.
        #expect(env.log.calls == [
            "link",
            "fetchLikes", "deleteAllData", "deleteCurrentUser",
            "signIn", "ensureUserDocument",
            "fetchLikes", "setLikes",
        ])
        #expect(analyticsUserIDs.last == "google-user")
    }

    @Test func `Credential in use sign in failure keeps pending and next start merges it`() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        env.auth.setSignInError(FakeAuthBackend.Failure())
        await env.manager.start()
        env.likes.seed([like(1, at: t1), like(2, at: t3)], uid: "anon-1")

        await #expect(throws: FakeAuthBackend.Failure.self, "signIn should rethrow the sign-in failure") {
            try await env.manager.signIn(with: googleCredential())
        }

        // The anonymous user is gone, but its likes are kept on the device.
        #expect(env.manager.state == .signedOut)
        #expect(env.pending.load() == [like(2, at: t3), like(1, at: t1)])

        await env.manager.start()

        #expect(env.manager.state == .anonymous(uid: "anon-2"))
        #expect(env.likes.likes(for: "anon-2") == [like(2, at: t3), like(1, at: t1)])
        #expect(env.pending.load() == [])
    }

    @Test func `Credential in use merge write failure keeps pending for next start`() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(2, at: t3)], uid: "anon-1")
        env.likes.setSetLikesError(FakeLikesStore.Failure())

        try await env.manager.signIn(with: googleCredential())

        #expect(env.manager.state == .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        #expect(env.pending.load() == [like(2, at: t3)])

        env.likes.setSetLikesError(nil)
        await env.manager.start()

        #expect(env.likes.likes(for: "google-user") == [like(2, at: t3)])
        #expect(env.pending.load() == [])
    }

    @Test func `Credential in use read failure leaves anonymous account untouched`() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(2, at: t3)], uid: "anon-1")
        env.likes.setFetchError(FakeLikesStore.Failure())

        await #expect(throws: (any Error).self, "signIn should rethrow the read failure") {
            try await env.manager.signIn(with: googleCredential())
        }

        #expect(env.manager.state == .anonymous(uid: "anon-1"))
        #expect(env.likes.likes(for: "anon-1") == [like(2, at: t3)])
        #expect(env.auth.deletedUids == [])
        #expect(env.pending.load() == [])
    }

    @Test func `Sign in without account signs in and merges pending`() async throws {
        let env = try makeEnv()
        env.auth.setAnonymousSignInError(FakeAuthBackend.Failure())
        await env.manager.start()
        env.pending.save([like(2, at: t3)])

        try await env.manager.signIn(with: appleCredential())

        #expect(env.manager.state == .signedIn(uid: "new-apple.com", provider: .apple, email: nil))
        #expect(!env.auth.calls.contains("link"))
        #expect(env.likes.userDocuments["new-apple.com"] != nil)
        #expect(env.likes.likes(for: "new-apple.com") == [like(2, at: t3)])
        #expect(env.pending.load() == [])
    }

    // MARK: Overlapping operations

    @Test func `Overlapping sign ins keep the existing account`() async throws {
        let env = try makeEnv()
        // The existing account has both providers, so both credentials are "already in use".
        env.auth.addExistingAccount(googleUser, for: .google)
        env.auth.addExistingAccount(googleUser, for: .apple)
        env.likes.seed([like(1, at: t2)], uid: "google-user")
        await env.manager.start()
        env.likes.seed([like(1, at: t1), like(2, at: t3)], uid: "anon-1")
        // The second flow's cleanup is slow. Run concurrently, it would land after the first flow
        // signed in to the existing account, and delete that account's user.
        env.likes.setDeleteAllDataDelays([nil, .milliseconds(100)])
        env.log.reset()

        let google = googleCredential()
        let apple = appleCredential()
        let first = Task { try await env.manager.signIn(with: google) }
        let second = Task { try await env.manager.signIn(with: apple) }
        let firstResult = await first.result
        _ = await second.result

        #expect(throws: Never.self) { try firstResult.get() }
        // The second sign-in runs only after the first finished, so it starts from the existing
        // (non-anonymous) account and deletes nothing.
        #expect(env.log.calls == [
            "link", "fetchLikes", "deleteAllData", "deleteCurrentUser", "signIn", "ensureUserDocument",
            "fetchLikes", "setLikes",
            "link",
        ])
        #expect(env.auth.deletedUids == ["anon-1"])
        #expect(env.auth.currentUser?.uid == "google-user")
        #expect(env.manager.state == .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        #expect(env.likes.likes(for: "google-user") == [like(2, at: t3), like(1, at: t1)])
        #expect(env.pending.load() == [])
    }

    @Test func `Start during merge waits and pending lands in existing account`() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(1, at: t1), like(2, at: t3)], uid: "anon-1")
        env.auth.setSignInDelay(.milliseconds(100))

        let google = googleCredential()
        let signIn = Task { try await env.manager.signIn(with: google) }
        // The anonymous user is already deleted and the existing account not yet signed in.
        try await waitUntil { env.auth.calls.contains("signIn") }
        await env.manager.start()
        try await signIn.value

        #expect(env.auth.calls.filter { $0 == "signInAnonymously" }.count == 1, "no throwaway anonymous account")
        #expect(env.manager.state == .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        #expect(env.likes.likes(for: "google-user") == [like(2, at: t3), like(1, at: t1)])
        #expect(env.pending.load() == [])
    }

    @Test func `Merge deletes nothing when another user is signed in by cleanup time`() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(2, at: t3)], uid: "anon-1")
        let other = AuthUserInfo(uid: "other-user", isAnonymous: false, provider: .apple, email: nil)
        env.likes.seed([like(5, at: t1)], uid: "other-user")
        // Something outside the flow switches the session right after the anonymous likes are read.
        env.likes.setAfterFetchHook { [auth = env.auth] in auth.setCurrentUser(other) }

        try await env.manager.signIn(with: googleCredential())

        #expect(env.auth.deletedUids == [], "only the anonymous user it read may be deleted")
        #expect(env.likes.likes(for: "other-user") == [like(5, at: t1)])
        #expect(env.manager.state == .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        #expect(env.likes.likes(for: "google-user") == [like(2, at: t3)])
        #expect(env.pending.load() == [])
    }

    @Test func `Is busy while operations are queued`() async throws {
        let env = try makeEnv()
        env.auth.setAnonymousSignInDelay(.milliseconds(150))
        #expect(!env.manager.isBusy)

        let first = Task { await env.manager.start() }
        try await waitUntil { env.auth.calls.contains("signInAnonymously") }
        #expect(env.manager.isBusy, "busy while the first operation runs")

        // Queued behind the first; it signs in again after signing out, which takes another 150 ms.
        let second = Task { try await env.manager.signOut() }
        try await Task.sleep(for: .milliseconds(20))
        await first.value
        #expect(env.manager.isBusy, "still busy while the second operation waits and runs")

        try await second.value
        #expect(!env.manager.isBusy)
        #expect(env.manager.state == .anonymous(uid: "anon-2"))
    }

    @Test func `Is not busy after a failed operation`() async throws {
        let env = try makeEnv()
        await env.manager.start()

        await #expect(throws: AccountError.notSignedIn, "deleting an anonymous account should throw") {
            try await env.manager.deleteAccount(reauthWith: appleCredential())
        }
        #expect(!env.manager.isBusy)
    }

    // MARK: signOut

    @Test func `Sign out starts new anonymous account`() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()

        try await env.manager.signOut()

        #expect(env.manager.state == .anonymous(uid: "anon-1"))
        #expect(Array(env.auth.calls.suffix(2)) == ["signOut", "signInAnonymously"])
        #expect(analyticsUserIDs.last == "anon-1")
    }

    // MARK: deleteAccount

    @Test func `Delete Apple account call order`() async throws {
        let env = try makeEnv(currentUser: appleUser)
        env.likes.seed([like(1, at: t1)], uid: "apple-user")
        await env.manager.start()
        env.log.reset()

        try await env.manager.deleteAccount(reauthWith: appleCredential(code: "fresh-code"))

        // The brief's sequence, followed by the user-document check of the fresh anonymous account.
        #expect(env.log.calls == [
            "reauthenticate", "revokeAppleToken", "deleteAllData", "deleteWaitingPhotos", "deleteCurrentUser",
            "signInAnonymously", "ensureUserDocument",
        ])
        #expect(env.auth.revokedCodes == ["fresh-code"])
        #expect(env.auth.deletedUids == ["apple-user"])
        #expect(env.photos.deletedUids == ["apple-user"])
        #expect(env.likes.likes(for: "apple-user") == [])
        #expect(env.likes.userDocuments["apple-user"] == nil)
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
    }

    @Test func `Delete Google account skips revoke`() async throws {
        let env = try makeEnv(currentUser: googleUser)
        await env.manager.start()
        env.log.reset()

        try await env.manager.deleteAccount(reauthWith: googleCredential())

        #expect(env.log.calls == [
            "reauthenticate", "deleteAllData", "deleteWaitingPhotos", "deleteCurrentUser", "signInAnonymously",
            "ensureUserDocument",
        ])
        #expect(env.auth.revokedCodes == [])
        #expect(env.photos.deletedUids == ["google-user"])
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
    }

    @Test func `Delete Apple account without code throws missing token`() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()
        env.log.reset()

        await #expect(throws: SignInError.missingToken, "deleteAccount should throw") {
            try await env.manager.deleteAccount(reauthWith: appleCredential(code: nil))
        }

        #expect(!env.log.calls.contains("deleteAllData"))
        #expect(!env.log.calls.contains("deleteCurrentUser"))
        #expect(env.manager.state == .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))
    }

    @Test func `Delete account requires signed in account`() async throws {
        let env = try makeEnv()
        await env.manager.start()
        env.log.reset()

        await #expect(throws: (any Error).self, "deleteAccount should throw for an anonymous account") {
            try await env.manager.deleteAccount(reauthWith: googleCredential())
        }

        #expect(env.log.calls == [])
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
    }

    @Test func `Delete account stops when waiting photos cannot be deleted`() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()
        env.photos.error = FakeLikesStore.Failure()

        await #expect(throws: FakeLikesStore.Failure.self, "the first attempt should fail") {
            try await env.manager.deleteAccount(reauthWith: appleCredential())
        }
        // The Firebase user must outlive its photos: with the user gone, nobody could delete them any more.
        #expect(env.auth.deletedUids == [])
        #expect(env.photos.deletedUids == [])
        #expect(env.manager.state == .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))

        env.photos.error = nil
        try await env.manager.deleteAccount(reauthWith: appleCredential())

        #expect(env.photos.deletedUids == ["apple-user"])
        #expect(env.auth.deletedUids == ["apple-user"])
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
    }

    @Test func `Delete account retry after failure succeeds`() async throws {
        let env = try makeEnv(currentUser: appleUser)
        env.likes.seed([like(1, at: t1)], uid: "apple-user")
        await env.manager.start()
        env.auth.failNextDeletes(1)

        await #expect(throws: FakeAuthBackend.Failure.self, "the first attempt should fail") {
            try await env.manager.deleteAccount(reauthWith: appleCredential())
        }
        // The data is already gone, but the account stays signed in so the person can retry.
        #expect(env.likes.likes(for: "apple-user") == [])
        #expect(env.manager.state == .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))

        try await env.manager.deleteAccount(reauthWith: appleCredential())

        #expect(env.likes.calls.filter { $0 == "deleteAllData" }.count == 2)
        #expect(env.auth.calls.filter { $0 == "deleteCurrentUser" }.count == 2)
        #expect(env.auth.deletedUids == ["apple-user"])
        #expect(env.manager.state == .anonymous(uid: "anon-1"))
    }
}
