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
/// or Google, plus sign-out and account deletion. Likes follow the account (`users/{uid}/likes`).
@MainActor
@Observable
final class AccountManager {
    private(set) var state: AccountState = .signedOut

    @ObservationIgnored private let auth: AuthBackend
    @ObservationIgnored private let likes: LikesStore
    @ObservationIgnored private let pending: PendingLikesStore
    @ObservationIgnored private let setAnalyticsUserID: (String) -> Void
    /// The latest `start()`. Each call waits for the previous one, so overlapping calls never
    /// create two anonymous accounts.
    @ObservationIgnored private var startTask: Task<Void, Never>?

    init(
        auth: AuthBackend,
        likes: LikesStore,
        pending: PendingLikesStore,
        setAnalyticsUserID: @escaping (String) -> Void = { Analytics.setUserID($0) }
    ) {
        self.auth = auth
        self.likes = likes
        self.pending = pending
        self.setAnalyticsUserID = setAnalyticsUserID
    }

    /// Signs in anonymously when there is no user, makes sure `users/{uid}` exists, merges any
    /// likes left pending by an interrupted sign-in, and sets the analytics user ID.
    /// Never throws: when the anonymous sign-in fails (e.g. offline) the state stays
    /// `.signedOut`, and a later call tries again.
    func start() async {
        let previous = startTask
        let task = Task {
            await previous?.value
            await performStart()
        }
        startTask = task
        await task.value
        if startTask == task { startTask = nil }
    }

    /// Links the credential to the current anonymous account, keeping its uid and likes.
    ///
    /// When the credential already belongs to an account, that account wins: the anonymous
    /// likes are read and kept on the device, the anonymous account is deleted (while still
    /// signed in as it, because the rules only let a user touch their own data), then the
    /// existing account is signed in and the likes are merged into it. If that sign-in fails the
    /// error is rethrown and the likes stay on the device until the next `start()` merges them.
    func signIn(with credential: ProviderCredential) async throws {
        // A sign-in racing the launch `start()` must not be replaced by its anonymous account.
        await startTask?.value

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

    /// Signs out, then starts a fresh anonymous account.
    func signOut() async throws {
        try auth.signOut()
        state = .signedOut
        await start()
    }

    /// Re-authenticates, revokes the Apple token (Apple accounts), deletes the account's data
    /// and the Firebase user, then starts a fresh anonymous account. Every step can run again,
    /// so after a failure the person can simply retry.
    func deleteAccount(reauthWith credential: ProviderCredential) async throws {
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
        try await likes.deleteAllData(uid: uid)
        try await auth.deleteCurrentUser()

        pending.clear()
        state = .signedOut
        await start()
    }

    // MARK: Private

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

    /// Makes `user` the current account: updates the state, makes sure `users/{uid}` exists,
    /// merges pending likes and sets the analytics user ID.
    private func adopt(_ user: AuthUserInfo) async {
        state = AccountState(user)
        do {
            try await likes.ensureUserDocument(uid: user.uid)
        } catch {
            // Not fatal: likes work without it, and the next start() tries again.
            Self.logger.error("Could not create the user document: \(error.localizedDescription, privacy: .public)")
        }
        await mergePendingLikes(into: user.uid)
        setAnalyticsUserID(user.uid)
    }

    private func switchToExistingAccount(from anonymous: AuthUserInfo, using credential: ProviderCredential) async throws {
        // 1. Read the anonymous likes while still signed in as that user, and keep them on the device.
        //    If the read fails, nothing has changed yet and the error is rethrown.
        let anonymousLikes = try await likes.fetchLikes(uid: anonymous.uid)
        pending.save(LikesMerge.merge(existing: pending.load(), incoming: anonymousLikes))

        // 2. Clean up the anonymous account. A failure only leaves orphaned anonymous data;
        //    the likes are safe in `pending`.
        do {
            try await likes.deleteAllData(uid: anonymous.uid)
        } catch {
            Self.logger.error("Could not delete anonymous data: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try await auth.deleteCurrentUser()
        } catch {
            Self.logger.error("Could not delete the anonymous user: \(error.localizedDescription, privacy: .public)")
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

        // 4–5. Make sure the user document exists, then merge the pending likes and clear them.
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
