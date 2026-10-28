import XCTest
import FirebaseAuth
@testable import Wuserade

@MainActor
final class AccountManagerTests: XCTestCase {
    /// XCTest creates one instance per test method, so every test gets its own defaults suite.
    private let suiteName = "AccountManagerTests-\(UUID().uuidString)"
    private var analyticsUserIDs: [String] = []

    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_002_000)

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: Fixtures

    private struct Env {
        let manager: AccountManager
        let auth: FakeAuthBackend
        let likes: FakeLikesStore
        let pending: PendingLikesStore
        let log: CallLog
    }

    /// The likes fake enforces the security rules: only the signed-in uid can touch its data.
    private func makeEnv(currentUser: AuthUserInfo? = nil) throws -> Env {
        let log = CallLog()
        let auth = FakeAuthBackend(currentUser: currentUser, log: log)
        let likes = FakeLikesStore(log: log, ownerUid: { [auth] in auth.currentUser?.uid })
        let pending = PendingLikesStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let manager = AccountManager(auth: auth, likes: likes, pending: pending) { [weak self] uid in
            self?.analyticsUserIDs.append(uid)
        }
        return Env(manager: manager, auth: auth, likes: likes, pending: pending, log: log)
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

    func testStartSignsInAnonymouslyOnce() async throws {
        let env = try makeEnv()
        // Overlapping calls (e.g. launch plus a sign-out) must not create two anonymous accounts.
        env.auth.setAnonymousSignInDelay(.milliseconds(50))
        async let first: Void = env.manager.start()
        async let second: Void = env.manager.start()
        _ = await (first, second)
        await env.manager.start()

        XCTAssertEqual(env.auth.calls.filter { $0 == "signInAnonymously" }.count, 1)
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
        XCTAssertEqual(env.manager.state.uid, "anon-1")
        XCTAssertNotNil(env.likes.userDocuments["anon-1"])
        XCTAssertEqual(analyticsUserIDs.last, "anon-1")
    }

    func testStartKeepsExistingUser() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()

        XCTAssertFalse(env.auth.calls.contains("signInAnonymously"))
        XCTAssertEqual(env.manager.state, .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))
        XCTAssertEqual(env.likes.calls, ["ensureUserDocument"])
        XCTAssertEqual(analyticsUserIDs, ["apple-user"])
    }

    func testStartFailureStaysSignedOutAndALaterStartRetries() async throws {
        let env = try makeEnv()
        env.auth.setAnonymousSignInError(FakeAuthBackend.Failure())
        await env.manager.start()

        XCTAssertEqual(env.manager.state, .signedOut)
        XCTAssertNil(env.manager.state.uid)
        XCTAssertEqual(env.likes.calls, [])
        XCTAssertEqual(analyticsUserIDs, [])

        env.auth.setAnonymousSignInError(nil)
        await env.manager.start()
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
    }

    // MARK: signIn

    func testLinkSuccessKeepsUid() async throws {
        let env = try makeEnv()
        await env.manager.start()
        env.likes.resetCalls()

        try await env.manager.signIn(with: appleCredential())

        XCTAssertEqual(env.manager.state, .signedIn(uid: "anon-1", provider: .apple, email: "anon-1@example.com"))
        XCTAssertEqual(env.likes.calls, [])
    }

    func testCredentialInUseMergesAnonymousLikes() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        env.likes.seed([like(1, at: t2)], uid: "google-user")
        await env.manager.start()
        env.likes.seed([like(1, at: t1), like(2, at: t3)], uid: "anon-1")
        env.log.reset()

        try await env.manager.signIn(with: googleCredential())

        XCTAssertEqual(env.manager.state, .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        XCTAssertEqual(env.likes.likes(for: "google-user"), [like(2, at: t3), like(1, at: t1)])
        // The anonymous account's data and user are gone.
        XCTAssertEqual(env.likes.likes(for: "anon-1"), [])
        XCTAssertNil(env.likes.userDocuments["anon-1"])
        XCTAssertEqual(env.auth.deletedUids, ["anon-1"])
        XCTAssertEqual(env.pending.load(), [])
        // The anonymous data is read and deleted while still signed in as the anonymous user,
        // because the rules only let a user touch their own data.
        XCTAssertEqual(env.log.calls, [
            "link",
            "fetchLikes", "deleteAllData", "deleteCurrentUser",
            "signIn", "ensureUserDocument",
            "fetchLikes", "setLikes",
        ])
        XCTAssertEqual(analyticsUserIDs.last, "google-user")
    }

    func testCredentialInUseSignInFailureKeepsPendingAndNextStartMergesIt() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        env.auth.setSignInError(FakeAuthBackend.Failure())
        await env.manager.start()
        env.likes.seed([like(1, at: t1), like(2, at: t3)], uid: "anon-1")

        do {
            try await env.manager.signIn(with: googleCredential())
            XCTFail("signIn should rethrow the sign-in failure")
        } catch {
            XCTAssertTrue(error is FakeAuthBackend.Failure, "unexpected error \(error)")
        }

        // The anonymous user is gone, but its likes are kept on the device.
        XCTAssertEqual(env.manager.state, .signedOut)
        XCTAssertEqual(env.pending.load(), [like(2, at: t3), like(1, at: t1)])

        await env.manager.start()

        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-2"))
        XCTAssertEqual(env.likes.likes(for: "anon-2"), [like(2, at: t3), like(1, at: t1)])
        XCTAssertEqual(env.pending.load(), [])
    }

    func testCredentialInUseMergeWriteFailureKeepsPendingForNextStart() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(2, at: t3)], uid: "anon-1")
        env.likes.setSetLikesError(FakeLikesStore.Failure())

        try await env.manager.signIn(with: googleCredential())

        XCTAssertEqual(env.manager.state, .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        XCTAssertEqual(env.pending.load(), [like(2, at: t3)])

        env.likes.setSetLikesError(nil)
        await env.manager.start()

        XCTAssertEqual(env.likes.likes(for: "google-user"), [like(2, at: t3)])
        XCTAssertEqual(env.pending.load(), [])
    }

    func testCredentialInUseReadFailureLeavesAnonymousAccountUntouched() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(2, at: t3)], uid: "anon-1")
        env.likes.setFetchError(FakeLikesStore.Failure())

        do {
            try await env.manager.signIn(with: googleCredential())
            XCTFail("signIn should rethrow the read failure")
        } catch {}

        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
        XCTAssertEqual(env.likes.likes(for: "anon-1"), [like(2, at: t3)])
        XCTAssertEqual(env.auth.deletedUids, [])
        XCTAssertEqual(env.pending.load(), [])
    }

    func testSignInWithoutAccountSignsInAndMergesPending() async throws {
        let env = try makeEnv()
        env.auth.setAnonymousSignInError(FakeAuthBackend.Failure())
        await env.manager.start()
        env.pending.save([like(2, at: t3)])

        try await env.manager.signIn(with: appleCredential())

        XCTAssertEqual(env.manager.state, .signedIn(uid: "new-apple.com", provider: .apple, email: nil))
        XCTAssertFalse(env.auth.calls.contains("link"))
        XCTAssertNotNil(env.likes.userDocuments["new-apple.com"])
        XCTAssertEqual(env.likes.likes(for: "new-apple.com"), [like(2, at: t3)])
        XCTAssertEqual(env.pending.load(), [])
    }

    // MARK: Overlapping operations

    func testOverlappingSignInsKeepTheExistingAccount() async throws {
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

        XCTAssertNoThrow(try firstResult.get())
        // The second sign-in runs only after the first finished, so it starts from the existing
        // (non-anonymous) account and deletes nothing.
        XCTAssertEqual(env.log.calls, [
            "link", "fetchLikes", "deleteAllData", "deleteCurrentUser", "signIn", "ensureUserDocument",
            "fetchLikes", "setLikes",
            "link",
        ])
        XCTAssertEqual(env.auth.deletedUids, ["anon-1"])
        XCTAssertEqual(env.auth.currentUser?.uid, "google-user")
        XCTAssertEqual(env.manager.state, .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        XCTAssertEqual(env.likes.likes(for: "google-user"), [like(2, at: t3), like(1, at: t1)])
        XCTAssertEqual(env.pending.load(), [])
    }

    func testStartDuringMergeWaitsAndPendingLandsInExistingAccount() async throws {
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

        XCTAssertEqual(env.auth.calls.filter { $0 == "signInAnonymously" }.count, 1, "no throwaway anonymous account")
        XCTAssertEqual(env.manager.state, .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        XCTAssertEqual(env.likes.likes(for: "google-user"), [like(2, at: t3), like(1, at: t1)])
        XCTAssertEqual(env.pending.load(), [])
    }

    func testMergeDeletesNothingWhenAnotherUserIsSignedInByCleanupTime() async throws {
        let env = try makeEnv()
        env.auth.addExistingAccount(googleUser, for: .google)
        await env.manager.start()
        env.likes.seed([like(2, at: t3)], uid: "anon-1")
        let other = AuthUserInfo(uid: "other-user", isAnonymous: false, provider: .apple, email: nil)
        env.likes.seed([like(5, at: t1)], uid: "other-user")
        // Something outside the flow switches the session right after the anonymous likes are read.
        env.likes.setAfterFetchHook { [auth = env.auth] in auth.setCurrentUser(other) }

        try await env.manager.signIn(with: googleCredential())

        XCTAssertEqual(env.auth.deletedUids, [], "only the anonymous user it read may be deleted")
        XCTAssertEqual(env.likes.likes(for: "other-user"), [like(5, at: t1)])
        XCTAssertEqual(env.manager.state, .signedIn(uid: "google-user", provider: .google, email: "g@example.com"))
        XCTAssertEqual(env.likes.likes(for: "google-user"), [like(2, at: t3)])
        XCTAssertEqual(env.pending.load(), [])
    }

    func testIsBusyWhileOperationsAreQueued() async throws {
        let env = try makeEnv()
        env.auth.setAnonymousSignInDelay(.milliseconds(150))
        XCTAssertFalse(env.manager.isBusy)

        let first = Task { await env.manager.start() }
        try await waitUntil { env.auth.calls.contains("signInAnonymously") }
        XCTAssertTrue(env.manager.isBusy, "busy while the first operation runs")

        // Queued behind the first; it signs in again after signing out, which takes another 150 ms.
        let second = Task { try await env.manager.signOut() }
        try await Task.sleep(for: .milliseconds(20))
        await first.value
        XCTAssertTrue(env.manager.isBusy, "still busy while the second operation waits and runs")

        try await second.value
        XCTAssertFalse(env.manager.isBusy)
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-2"))
    }

    func testIsNotBusyAfterAFailedOperation() async throws {
        let env = try makeEnv()
        await env.manager.start()

        do {
            try await env.manager.deleteAccount(reauthWith: appleCredential())
            XCTFail("deleting an anonymous account should throw")
        } catch {
            XCTAssertEqual(error as? AccountError, .notSignedIn)
        }
        XCTAssertFalse(env.manager.isBusy)
    }

    // MARK: signOut

    func testSignOutStartsNewAnonymousAccount() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()

        try await env.manager.signOut()

        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
        XCTAssertEqual(Array(env.auth.calls.suffix(2)), ["signOut", "signInAnonymously"])
        XCTAssertEqual(analyticsUserIDs.last, "anon-1")
    }

    // MARK: deleteAccount

    func testDeleteAppleAccountCallOrder() async throws {
        let env = try makeEnv(currentUser: appleUser)
        env.likes.seed([like(1, at: t1)], uid: "apple-user")
        await env.manager.start()
        env.log.reset()

        try await env.manager.deleteAccount(reauthWith: appleCredential(code: "fresh-code"))

        // The brief's sequence, followed by the user-document check of the fresh anonymous account.
        XCTAssertEqual(env.log.calls, [
            "reauthenticate", "revokeAppleToken", "deleteAllData", "deleteCurrentUser", "signInAnonymously",
            "ensureUserDocument",
        ])
        XCTAssertEqual(env.auth.revokedCodes, ["fresh-code"])
        XCTAssertEqual(env.auth.deletedUids, ["apple-user"])
        XCTAssertEqual(env.likes.likes(for: "apple-user"), [])
        XCTAssertNil(env.likes.userDocuments["apple-user"])
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
    }

    func testDeleteGoogleAccountSkipsRevoke() async throws {
        let env = try makeEnv(currentUser: googleUser)
        await env.manager.start()
        env.log.reset()

        try await env.manager.deleteAccount(reauthWith: googleCredential())

        XCTAssertEqual(env.log.calls, [
            "reauthenticate", "deleteAllData", "deleteCurrentUser", "signInAnonymously", "ensureUserDocument",
        ])
        XCTAssertEqual(env.auth.revokedCodes, [])
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
    }

    func testDeleteAppleAccountWithoutCodeThrowsMissingToken() async throws {
        let env = try makeEnv(currentUser: appleUser)
        await env.manager.start()
        env.log.reset()

        do {
            try await env.manager.deleteAccount(reauthWith: appleCredential(code: nil))
            XCTFail("deleteAccount should throw")
        } catch {
            XCTAssertEqual(error as? SignInError, .missingToken)
        }

        XCTAssertFalse(env.log.calls.contains("deleteAllData"))
        XCTAssertFalse(env.log.calls.contains("deleteCurrentUser"))
        XCTAssertEqual(env.manager.state, .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))
    }

    func testDeleteAccountRequiresSignedInAccount() async throws {
        let env = try makeEnv()
        await env.manager.start()
        env.log.reset()

        do {
            try await env.manager.deleteAccount(reauthWith: googleCredential())
            XCTFail("deleteAccount should throw for an anonymous account")
        } catch {}

        XCTAssertEqual(env.log.calls, [])
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
    }

    func testDeleteAccountRetryAfterFailureSucceeds() async throws {
        let env = try makeEnv(currentUser: appleUser)
        env.likes.seed([like(1, at: t1)], uid: "apple-user")
        await env.manager.start()
        env.auth.failNextDeletes(1)

        do {
            try await env.manager.deleteAccount(reauthWith: appleCredential())
            XCTFail("the first attempt should fail")
        } catch {
            XCTAssertTrue(error is FakeAuthBackend.Failure, "unexpected error \(error)")
        }
        // The data is already gone, but the account stays signed in so the person can retry.
        XCTAssertEqual(env.likes.likes(for: "apple-user"), [])
        XCTAssertEqual(env.manager.state, .signedIn(uid: "apple-user", provider: .apple, email: "a@example.com"))

        try await env.manager.deleteAccount(reauthWith: appleCredential())

        XCTAssertEqual(env.likes.calls.filter { $0 == "deleteAllData" }.count, 2)
        XCTAssertEqual(env.auth.calls.filter { $0 == "deleteCurrentUser" }.count, 2)
        XCTAssertEqual(env.auth.deletedUids, ["apple-user"])
        XCTAssertEqual(env.manager.state, .anonymous(uid: "anon-1"))
    }
}
