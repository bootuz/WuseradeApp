import FirebaseAnalytics
import Foundation
import Observation
import os

enum AccountState: Equatable {
    /// No Firebase user yet, e.g. the anonymous sign-in failed offline. Reading still works.
    case signedOut
    case anonymous(uid: String)
    case signedIn(uid: String, provider: SignInProvider, email: String?)

    var uid: String? {
        switch self {
        case .signedOut:
            return nil
        case let .anonymous(uid), let .signedIn(uid, _, _):
            return uid
        }
    }
}

enum AccountError: Error, Equatable {
    /// Only an Apple or Google account can be deleted.
    case notSignedIn
}

/// Owns the Firebase account: a silent anonymous account on launch, upgraded by linking Apple
/// or Google, plus sign-out and account deletion. Likes and the reading history follow the account
/// (`users/{uid}/likes` and `users/{uid}/reads`).
///
/// `start`, `signIn`, `signOut` and `deleteAccount` run one at a time, in the order they were
/// called: each waits for the ones before it, then runs against the account as it is by then.
/// So two quick taps, or a `start()` arriving mid sign-in, can never act on a half-switched
/// session.
@MainActor
@Observable
final class AccountManager {
    private(set) var state: AccountState = .signedOut
    /// True from the moment `start`, `signIn`, `signOut` or `deleteAccount` is called until every
    /// operation queued so far has finished. Likes are off while it is true: a sign-in reads the
    /// anonymous likes and then deletes them, so a like written in between would be lost.
    private(set) var isBusy = false

    @ObservationIgnored private let auth: AuthBackend
    @ObservationIgnored private let likes: LikesStore
    @ObservationIgnored private let pending: PendingLikesStore
    @ObservationIgnored private let reads: any ReadsStore
    /// Reads of an anonymous account waiting to be uploaded to the account that replaces it.
    @ObservationIgnored private let pendingReads: PendingReadsStore
    /// Deletes the photos `uid` sent that still wait for review. Only `deleteAccount` calls it.
    @ObservationIgnored private let deleteWaitingPhotos: @MainActor (_ uid: String) async throws -> Void
    @ObservationIgnored private let setAnalyticsUserID: (String) -> Void
    /// The last queued operation. A new operation waits for it before running.
    @ObservationIgnored private var lastOperation: Task<Result<Void, Error>, Never>?
    /// Operations that are queued or running; `isBusy` is true while there are any.
    @ObservationIgnored private var pendingOperations = 0

    init(
        auth: AuthBackend,
        likes: LikesStore,
        pending: PendingLikesStore,
        reads: any ReadsStore,
        pendingReads: PendingReadsStore,
        deleteWaitingPhotos: @escaping @MainActor (_ uid: String) async throws -> Void,
        setAnalyticsUserID: @escaping (String) -> Void = { Analytics.setUserID($0) }
    ) {
        self.auth = auth
        self.likes = likes
        self.pending = pending
        self.reads = reads
        self.pendingReads = pendingReads
        self.deleteWaitingPhotos = deleteWaitingPhotos
        self.setAnalyticsUserID = setAnalyticsUserID
    }

    /// Signs in anonymously when there is no user, makes sure `users/{uid}` exists, merges any
    /// likes left pending by an interrupted sign-in, and sets the analytics user ID.
    /// Never throws: when the anonymous sign-in fails (e.g. offline) the state stays
    /// `.signedOut`, and a later call tries again.
    func start() async {
        // `performStart` never throws, so there is no error to drop here.
        try? await serialized { await self.performStart() }
    }

    /// Links the credential to the current anonymous account, keeping its uid and likes.
    ///
    /// When the credential already belongs to an account, that account wins: the anonymous
    /// likes are read and kept on the device, the anonymous account is deleted (while still
    /// signed in as it, because the rules only let a user touch their own data), then the
    /// existing account is signed in and the likes are merged into it. If that sign-in fails the
    /// error is rethrown and the likes stay on the device until the next `start()` merges them.
    func signIn(with credential: ProviderCredential) async throws {
        try await serialized { try await self.performSignIn(with: credential) }
    }

    /// Signs out, then starts a fresh anonymous account.
    func signOut() async throws {
        try await serialized { try await self.performSignOut() }
    }

    /// Re-authenticates, revokes the Apple token (Apple accounts), deletes the account's reads and data,
    /// then its waiting photos, then the Firebase user, and starts a fresh anonymous account. The photos
    /// go first because the rules only let the signed-in user delete them: if that fails the user
    /// stays, so nothing is left that no one could delete. Every step can run again, so after a
    /// failure the person can simply retry.
    func deleteAccount(reauthWith credential: ProviderCredential) async throws {
        try await serialized { try await self.performDeleteAccount(reauthWith: credential) }
    }

    // MARK: Operations
    //
    // These run inside the chain. They call each other directly, never the public methods,
    // which would wait for the very operation that is calling them.

    /// Queues `operation` behind every earlier one and waits for it to finish.
    private func serialized(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        pendingOperations += 1
        isBusy = true
        defer {
            pendingOperations -= 1
            isBusy = pendingOperations > 0
        }

        let previous = lastOperation
        let task = Task { () -> Result<Void, Error> in
            _ = await previous?.value
            do {
                try await operation()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        lastOperation = task
        let result = await task.value
        if lastOperation == task { lastOperation = nil }
        try result.get()
    }

    private func performStart() async {
        let user: AuthUserInfo
        if let current = auth.currentUser {
            user = current
        } else {
            do {
                user = try await auth.signInAnonymously()
            } catch {
                Self.logger.error("Anonymous sign-in failed: \(error.localizedDescription, privacy: .public)")
                state = .signedOut
                return
            }
        }
        await adopt(user)
    }

    private func performSignIn(with credential: ProviderCredential) async throws {
        guard let current = auth.currentUser else {
            // No account at all (the anonymous sign-in failed): sign in directly.
            await adopt(try await auth.signIn(with: credential))
            return
        }

        do {
            state = AccountState(try await auth.link(credential))
        } catch let AuthBackendError.credentialAlreadyInUse(existing) where current.isAnonymous {
            try await switchToExistingAccount(from: current, using: existing)
        }
    }

    private func performSignOut() async throws {
        try auth.signOut()
        state = .signedOut
        await performStart()
    }

    private func performDeleteAccount(reauthWith credential: ProviderCredential) async throws {
        guard case let .signedIn(uid, provider, _) = state else { throw AccountError.notSignedIn }
        var appleAuthorizationCode: String?
        if provider == .apple {
            guard credential.provider == .apple, let code = credential.appleAuthorizationCode else {
                throw SignInError.missingToken
            }
            appleAuthorizationCode = code
        }

        try await auth.reauthenticate(with: credential)
        if let appleAuthorizationCode {
            try await auth.revokeAppleToken(authorizationCode: appleAuthorizationCode)
        }
        try await reads.deleteAllReads(uid: uid)
        try await likes.deleteAllData(uid: uid)
        try await deleteWaitingPhotos(uid)
        try await auth.deleteCurrentUser(expectedUID: uid)

        pending.clear()
        pendingReads.clear()
        state = .signedOut
        await performStart()
    }

    // MARK: Helpers

    /// Makes `user` the current account: updates the state, makes sure `users/{uid}` exists,
    /// merges pending likes, uploads pending reads and sets the analytics user ID.
    private func adopt(_ user: AuthUserInfo) async {
        state = AccountState(user)
        do {
            try await likes.ensureUserDocument(uid: user.uid)
        } catch {
            // Not fatal: likes work without it, and the next start() tries again.
            Self.logger.error("Could not create the user document: \(error.localizedDescription, privacy: .public)")
        }
        await mergePendingLikes(into: user.uid)
        await uploadPendingReads(to: user.uid)
        setAnalyticsUserID(user.uid)
    }

    private func switchToExistingAccount(from anonymous: AuthUserInfo, using credential: ProviderCredential) async throws {
        // 1. Read the anonymous likes and reads while still signed in as that user, and keep them on the device.
        //    If either read fails, nothing has changed yet and the error is rethrown.
        let anonymousReads = try await reads.fetchReadIDs(uid: anonymous.uid)
        let anonymousLikes = try await likes.fetchLikes(uid: anonymous.uid)
        pending.save(LikesMerge.merge(existing: pending.load(), incoming: anonymousLikes))
        pendingReads.save(pendingReads.load().union(anonymousReads))

        // 2. Clean up the anonymous account, but only while it is still the signed-in user: deleting
        //    "the current user" must never hit anyone else. Skipping or failing only leaves orphaned
        //    anonymous data; the likes and reads are safe in `pending` and `pendingReads`.
        if let signedIn = auth.currentUser, signedIn.uid == anonymous.uid, signedIn.isAnonymous {
            do {
                try await reads.deleteAllReads(uid: anonymous.uid)
            } catch {
                Self.logger.error("Could not delete anonymous reads: \(error.localizedDescription, privacy: .public)")
            }
            do {
                try await likes.deleteAllData(uid: anonymous.uid)
            } catch {
                Self.logger.error("Could not delete anonymous data: \(error.localizedDescription, privacy: .public)")
            }
            do {
                try await auth.deleteCurrentUser(expectedUID: anonymous.uid)
            } catch {
                Self.logger.error("Could not delete the anonymous user: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            Self.logger.error("The anonymous user is no longer signed in; skipping its cleanup")
        }
        state = AccountState(auth.currentUser)

        // 3. Sign in to the existing account. On failure the pending likes stay for the next start().
        let user: AuthUserInfo
        do {
            user = try await auth.signIn(with: credential)
        } catch {
            state = AccountState(auth.currentUser)
            throw error
        }

        // 4–5. Make sure the user document exists, then merge the pending likes and reads and clear them.
        await adopt(user)
    }

    /// Writes the pending likes into `uid`, keeping the earliest `likedAt` per poem, then clears
    /// them. Only likes that add or change something are written. On failure they stay pending.
    private func mergePendingLikes(into uid: String) async {
        let saved = pending.load()
        guard !saved.isEmpty else { return }
        do {
            let existing = try await likes.fetchLikes(uid: uid)
            let unchanged = Set(existing)
            let changes = LikesMerge.merge(existing: existing, incoming: saved).filter { !unchanged.contains($0) }
            if !changes.isEmpty {
                try await likes.setLikes(changes, uid: uid)
            }
            pending.clear()
        } catch {
            Self.logger.error("Could not merge pending likes: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes each pending read into `uid`, then clears them. A read that cannot be written is dropped: the
    /// history only steers suggestions, so losing one is better than retrying it forever.
    private func uploadPendingReads(to uid: String) async {
        let saved = pendingReads.load()
        guard !saved.isEmpty else { return }
        for poemId in saved.sorted() {
            do {
                try await reads.markRead(poemId: poemId, uid: uid)
            } catch {
                Self.logger.error("Could not upload the read of poem \(poemId): \(error.localizedDescription, privacy: .public)")
            }
        }
        pendingReads.clear()
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "AccountManager"
    )
}

extension AccountState {
    init(_ user: AuthUserInfo?) {
        guard let user else {
            self = .signedOut
            return
        }
        if !user.isAnonymous, let provider = user.provider {
            self = .signedIn(uid: user.uid, provider: provider, email: user.email)
        } else {
            // A non-anonymous user without Apple or Google is never created by this app;
            // it is treated like an anonymous one so likes keep working.
            self = .anonymous(uid: user.uid)
        }
    }
}
