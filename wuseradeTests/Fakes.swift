import Foundation
@testable import Wuserade

/// In-memory `ContentRepository` for tests. Never touches Firestore or the network.
/// Records how often each read was made so tests can prove what did, and did not, hit the repository.
final class FakeContentRepository: ContentRepository, @unchecked Sendable {
    struct Offline: Error {}
    struct NotFound: Error {}

    private let lock = NSLock()
    private var _meta: ContentMeta
    private var _chunks: [Int: CatalogChunk]
    private var _poems: [Int: Poem]
    private var _isOffline = false
    private var _metaCalls = 0
    private var _chunkCalls = 0
    private var _poemCalls: [Int] = []
    /// Chunk indices that answer late, so tests can prove results are kept in index order
    /// even when chunks finish out of order.
    private var _slowChunks: Set<Int> = []

    init(
        meta: ContentMeta = FakeContentRepository.emptyMeta,
        chunks: [CatalogChunk] = [],
        poems: [Poem] = []
    ) {
        _meta = meta
        _chunks = Dictionary(uniqueKeysWithValues: chunks.enumerated().map { ($0.offset, $0.element) })
        _poems = Dictionary(uniqueKeysWithValues: poems.map { ($0.id, $0) })
    }

    static let emptyMeta = ContentMeta(
        catalogVersion: 1,
        catalogChunks: 0,
        authors: [],
        themes: [],
        nextPoemId: 1,
        minimumAppVersion: nil
    )

    var metaCalls: Int { lock.withLock { _metaCalls } }
    var chunkCalls: Int { lock.withLock { _chunkCalls } }
    /// The id of every `fetchPoem` call, in call order.
    var poemCalls: [Int] { lock.withLock { _poemCalls } }

    func set(meta: ContentMeta, chunks: [CatalogChunk]) {
        lock.withLock {
            _meta = meta
            _chunks = Dictionary(uniqueKeysWithValues: chunks.enumerated().map { ($0.offset, $0.element) })
        }
    }

    func set(poems: [Poem]) {
        lock.withLock {
            _poems = Dictionary(uniqueKeysWithValues: poems.map { ($0.id, $0) })
        }
    }

    func setOffline(_ offline: Bool) {
        lock.withLock { _isOffline = offline }
    }

    func setSlowChunks(_ indices: Set<Int>) {
        lock.withLock { _slowChunks = indices }
    }

    func resetCounts() {
        lock.withLock {
            _metaCalls = 0
            _chunkCalls = 0
            _poemCalls = []
        }
    }

    func fetchMeta() async throws -> ContentMeta {
        try lock.withLock {
            _metaCalls += 1
            if _isOffline { throw Offline() }
            return _meta
        }
    }

    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk {
        let (isSlow, chunk): (Bool, CatalogChunk) = try lock.withLock {
            _chunkCalls += 1
            if _isOffline { throw Offline() }
            guard let chunk = _chunks[index] else { throw Offline() }
            return (_slowChunks.contains(index), chunk)
        }
        if isSlow { try await Task.sleep(nanoseconds: 50_000_000) }
        return chunk
    }

    func fetchPoem(id: Int) async throws -> Poem {
        try lock.withLock {
            _poemCalls.append(id)
            if _isOffline { throw Offline() }
            guard let poem = _poems[id] else { throw NotFound() }
            return poem
        }
    }
}

/// Call names from one or more fakes, in the order they happened. Pass the same log to
/// `FakeAuthBackend` and `FakeLikesStore` to check the order of calls across both.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []

    var calls: [String] { lock.withLock { _calls } }

    func record(_ name: String) {
        lock.withLock { _calls.append(name) }
    }

    func reset() {
        lock.withLock { _calls = [] }
    }
}

/// In-memory `AuthBackend`. Anonymous users get the uids "anon-1", "anon-2", ... in order.
/// Credentials are told apart by their `provider` only; the `AuthCredential` inside is ignored.
final class FakeAuthBackend: AuthBackend, @unchecked Sendable {
    struct Failure: Error {}

    let log: CallLog
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _currentUser: AuthUserInfo?
    private var _anonymousCount = 0
    private var _existingAccounts: [SignInProvider: AuthUserInfo] = [:]
    private var _anonymousSignInError: Error?
    private var _anonymousSignInDelay: Duration?
    private var _signInError: Error?
    private var _deleteFailuresLeft = 0
    private var _deletedUids: [String] = []
    private var _revokedCodes: [String] = []

    init(currentUser: AuthUserInfo? = nil, log: CallLog = CallLog()) {
        _currentUser = currentUser
        if let currentUser, let provider = currentUser.provider {
            _existingAccounts[provider] = currentUser
        }
        self.log = log
    }

    /// Every call to this fake, in order.
    var calls: [String] { lock.withLock { _calls } }
    /// Users removed by `deleteCurrentUser`, in order.
    var deletedUids: [String] { lock.withLock { _deletedUids } }
    var revokedCodes: [String] { lock.withLock { _revokedCodes } }

    /// An account that already exists for `provider`. Linking a credential for that provider
    /// throws `.credentialAlreadyInUse`, and signing in with it returns this user.
    func addExistingAccount(_ user: AuthUserInfo, for provider: SignInProvider) {
        lock.withLock { _existingAccounts[provider] = user }
    }

    /// `signInAnonymously` throws this error until it is set back to nil (e.g. offline).
    func setAnonymousSignInError(_ error: Error?) {
        lock.withLock { _anonymousSignInError = error }
    }

    /// `signInAnonymously` waits this long before answering, so tests can overlap calls.
    func setAnonymousSignInDelay(_ delay: Duration?) {
        lock.withLock { _anonymousSignInDelay = delay }
    }

    /// `signIn(with:)` throws this error until it is set back to nil.
    func setSignInError(_ error: Error?) {
        lock.withLock { _signInError = error }
    }

    /// The next `count` calls to `deleteCurrentUser` throw `Failure`.
    func failNextDeletes(_ count: Int) {
        lock.withLock { _deleteFailuresLeft = count }
    }

    func resetCalls() {
        lock.withLock { _calls = [] }
    }

    private func record(_ name: String) {
        lock.withLock { _calls.append(name) }
        log.record(name)
    }

    var currentUser: AuthUserInfo? { lock.withLock { _currentUser } }

    func signInAnonymously() async throws -> AuthUserInfo {
        record("signInAnonymously")
        let (delay, error) = lock.withLock { (_anonymousSignInDelay, _anonymousSignInError) }
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        return lock.withLock {
            _anonymousCount += 1
            let user = AuthUserInfo(uid: "anon-\(_anonymousCount)", isAnonymous: true, provider: nil, email: nil)
            _currentUser = user
            return user
        }
    }

    func link(_ c: ProviderCredential) async throws -> AuthUserInfo {
        record("link")
        return try lock.withLock {
            guard let current = _currentUser else { throw Failure() }
            if _existingAccounts[c.provider] != nil {
                throw AuthBackendError.credentialAlreadyInUse(
                    ProviderCredential(
                        provider: c.provider,
                        credential: c.credential,
                        appleAuthorizationCode: c.appleAuthorizationCode
                    )
                )
            }
            let linked = AuthUserInfo(
                uid: current.uid,
                isAnonymous: false,
                provider: c.provider,
                email: "\(current.uid)@example.com"
            )
            _currentUser = linked
            _existingAccounts[c.provider] = linked
            return linked
        }
    }

    func signIn(with c: ProviderCredential) async throws -> AuthUserInfo {
        record("signIn")
        return try lock.withLock {
            if let error = _signInError { throw error }
            let user = _existingAccounts[c.provider]
                ?? AuthUserInfo(uid: "new-\(c.provider.rawValue)", isAnonymous: false, provider: c.provider, email: nil)
            _existingAccounts[c.provider] = user
            _currentUser = user
            return user
        }
    }

    func reauthenticate(with c: ProviderCredential) async throws {
        record("reauthenticate")
        try lock.withLock {
            guard _currentUser?.provider == c.provider else { throw Failure() }
        }
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        record("revokeAppleToken")
        lock.withLock { _revokedCodes.append(authorizationCode) }
    }

    func deleteCurrentUser() async throws {
        record("deleteCurrentUser")
        try lock.withLock {
            if _deleteFailuresLeft > 0 {
                _deleteFailuresLeft -= 1
                throw Failure()
            }
            guard let user = _currentUser else { return }
            _deletedUids.append(user.uid)
            _existingAccounts = _existingAccounts.filter { $0.value.uid != user.uid }
            _currentUser = nil
        }
    }

    func signOut() throws {
        record("signOut")
        lock.withLock { _currentUser = nil }
    }
}

/// In-memory `LikesStore`. When `ownerUid` is given it acts like the security rules: every call
/// for a uid other than the signed-in one throws `PermissionDenied`, so a flow that reads or
/// deletes another account's data in the wrong order fails.
final class FakeLikesStore: LikesStore, @unchecked Sendable {
    struct PermissionDenied: Error {}
    struct Failure: Error {}

    let log: CallLog
    private let ownerUid: (@Sendable () -> String?)?
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _likes: [String: [Int: Like]] = [:]
    private var _userDocuments: [String: Date] = [:]
    private var _setLikesError: Error?
    private var _fetchError: Error?
    private var _observers: [String: [UUID: AsyncThrowingStream<[Like], Error>.Continuation]] = [:]
    private var _cancelledObservations: [String] = []

    init(log: CallLog = CallLog(), ownerUid: (@Sendable () -> String?)? = nil) {
        self.log = log
        self.ownerUid = ownerUid
    }

    /// Every call to this fake, in order.
    var calls: [String] { lock.withLock { _calls } }
    /// uids that have a `users/{uid}` document, with its `createdAt`.
    var userDocuments: [String: Date] { lock.withLock { _userDocuments } }
    /// uids whose `observeLikes` stream ended, in order.
    var cancelledObservations: [String] { lock.withLock { _cancelledObservations } }

    /// The likes stored for `uid`, newest first.
    func likes(for uid: String) -> [Like] {
        lock.withLock { sorted(_likes[uid]) }
    }

    /// Stores likes directly, without recording a call or checking the owner.
    func seed(_ likes: [Like], uid: String) {
        lock.withLock {
            for like in likes { _likes[uid, default: [:]][like.poemId] = like }
        }
        notify(uid)
    }

    /// `setLikes` throws this error until it is set back to nil.
    func setSetLikesError(_ error: Error?) {
        lock.withLock { _setLikesError = error }
    }

    /// `fetchLikes` throws this error until it is set back to nil.
    func setFetchError(_ error: Error?) {
        lock.withLock { _fetchError = error }
    }

    func resetCalls() {
        lock.withLock { _calls = [] }
    }

    private func sorted(_ likes: [Int: Like]?) -> [Like] {
        (likes ?? [:]).values.sorted { ($0.likedAt, $0.poemId) > ($1.likedAt, $1.poemId) }
    }

    private func record(_ name: String, uid: String) throws {
        lock.withLock { _calls.append(name) }
        log.record(name)
        if let ownerUid, ownerUid() != uid { throw PermissionDenied() }
    }

    private func notify(_ uid: String) {
        let (current, observers) = lock.withLock {
            (sorted(_likes[uid]), Array((_observers[uid] ?? [:]).values))
        }
        for observer in observers { observer.yield(current) }
    }

    func fetchLikes(uid: String) async throws -> [Like] {
        try record("fetchLikes", uid: uid)
        return try lock.withLock {
            if let error = _fetchError { throw error }
            return sorted(_likes[uid])
        }
    }

    /// Emits the current likes at once, then again after every write for `uid`.
    func observeLikes(uid: String) -> AsyncThrowingStream<[Like], Error> {
        lock.withLock { _calls.append("observeLikes") }
        log.record("observeLikes")
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<[Like], Error>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                self._observers[uid]?[id] = nil
                self._cancelledObservations.append(uid)
            }
        }
        let current: [Like] = lock.withLock {
            _observers[uid, default: [:]][id] = continuation
            return sorted(_likes[uid])
        }
        continuation.yield(current)
        return stream
    }

    func setLike(_ like: Like, uid: String) async throws {
        try record("setLike", uid: uid)
        lock.withLock { _likes[uid, default: [:]][like.poemId] = like }
        notify(uid)
    }

    func setLikes(_ likes: [Like], uid: String) async throws {
        try record("setLikes", uid: uid)
        try lock.withLock {
            if let error = _setLikesError { throw error }
            for like in likes { _likes[uid, default: [:]][like.poemId] = like }
        }
        notify(uid)
    }

    func removeLike(poemId: Int, uid: String) async throws {
        try record("removeLike", uid: uid)
        lock.withLock { _ = _likes[uid]?.removeValue(forKey: poemId) }
        notify(uid)
    }

    func ensureUserDocument(uid: String) async throws {
        try record("ensureUserDocument", uid: uid)
        lock.withLock {
            if _userDocuments[uid] == nil { _userDocuments[uid] = .now }
        }
    }

    /// Idempotent, like the real store: deleting data that is already gone succeeds.
    func deleteAllData(uid: String) async throws {
        try record("deleteAllData", uid: uid)
        lock.withLock {
            _likes[uid] = nil
            _userDocuments[uid] = nil
        }
        notify(uid)
    }
}
