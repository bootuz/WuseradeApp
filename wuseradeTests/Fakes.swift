import Foundation
import Testing
import UserNotifications
@testable import Wuserade

/// Polls until `condition` holds (at most about two seconds), failing the test if it never does.
@MainActor
func waitUntil(
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ condition: () -> Bool
) async throws {
    for _ in 0 ..< 400 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record(
        "condition never became true",
        sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    )
}

/// In-memory `ContentRepository` for tests. Never touches Firestore or the network.
/// Records how often each read was made so tests can prove what did, and did not, hit the repository.
final class FakeContentRepository: ContentRepository, @unchecked Sendable {
    struct Offline: Error {}
    struct NotFound: Error {}
    struct Undecodable: Error {}

    private let lock = NSLock()
    private var _meta: ContentMeta
    private var _minimumAppVersion: String?
    private var _isMetaUndecodable = false
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
        nextPoemId: 1
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

    /// `meta/content.minimumAppVersion` from now on; nil leaves it out.
    func set(minimumAppVersion: String?) {
        lock.withLock { _minimumAppVersion = minimumAppVersion }
    }

    /// When true, the rest of `meta/content` fails to decode (a shape this build cannot read),
    /// while `minimumAppVersion` is still read.
    func setMetaUndecodable(_ undecodable: Bool) {
        lock.withLock { _isMetaUndecodable = undecodable }
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

    func fetchMeta() async throws -> MetaDocument {
        try lock.withLock {
            _metaCalls += 1
            if _isOffline { throw Offline() }
            return MetaDocument(
                minimumAppVersion: _minimumAppVersion,
                meta: _isMetaUndecodable ? .failure(Undecodable()) : .success(_meta)
            )
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
    private var _signInDelay: Duration?
    private var _signOutError: Error?
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

    /// `signIn(with:)` waits this long before answering, so tests can act while it is in flight.
    func setSignInDelay(_ delay: Duration?) {
        lock.withLock { _signInDelay = delay }
    }

    /// Replaces the signed-in user without recording a call, as a change made outside the
    /// code under test would (e.g. another flow, or Firebase signing the user out).
    func setCurrentUser(_ user: AuthUserInfo?) {
        lock.withLock { _currentUser = user }
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
        if let delay = lock.withLock({ _signInDelay }) { try await Task.sleep(for: delay) }
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

    /// Like `FirebaseAuthBackend`: deletes only the expected user, and nothing when no one is signed in.
    func deleteCurrentUser(expectedUID: String) async throws {
        record("deleteCurrentUser")
        try lock.withLock {
            if _deleteFailuresLeft > 0 {
                _deleteFailuresLeft -= 1
                throw Failure()
            }
            guard let user = _currentUser else { return }
            guard user.uid == expectedUID else { throw AuthBackendError.currentUserMismatch }
            _deletedUids.append(user.uid)
            _existingAccounts = _existingAccounts.filter { $0.value.uid != user.uid }
            _currentUser = nil
        }
    }

    func signOut() throws {
        record("signOut")
        try lock.withLock {
            if let _signOutError { throw _signOutError }
            _currentUser = nil
        }
    }

    /// `signOut` throws this error, keeping the user signed in, until it is set back to nil.
    func setSignOutError(_ error: Error?) {
        lock.withLock { _signOutError = error }
    }
}

/// In-memory `LikesStore`. When `ownerUid` is given it acts like the security rules: every call
/// for a uid other than the signed-in one throws `PermissionDenied`, so a flow that reads or
/// deletes another account's data in the wrong order fails.
final class FakeLikesStore: LikesStore, @unchecked Sendable {
    struct PermissionDenied: Error {}
    struct Failure: Error {}

    /// What one `setLike` or `removeLike` call does: it waits `delay`, then throws `error` if there
    /// is one, and otherwise stores the change. Like the real store, a call can hang before it answers.
    struct WriteOutcome {
        var delay: Duration?
        var error: Error?

        static func failure(after delay: Duration? = nil) -> WriteOutcome {
            WriteOutcome(delay: delay, error: Failure())
        }

        static func success(after delay: Duration? = nil) -> WriteOutcome {
            WriteOutcome(delay: delay, error: nil)
        }
    }

    let log: CallLog
    private let ownerUid: (@Sendable () -> String?)?
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _likes: [String: [Int: Like]] = [:]
    private var _userDocuments: [String: Date] = [:]
    private var _setLikesError: Error?
    private var _fetchError: Error?
    private var _afterFetchHook: (@Sendable () -> Void)?
    private var _deleteAllDataDelays: [Duration?] = []
    /// Upcoming outcomes by call name ("setLike", "removeLike"), consumed in call order.
    private var _writeOutcomes: [String: [WriteOutcome]] = [:]
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

    /// Runs once, right after the next successful `fetchLikes` has read its likes.
    func setAfterFetchHook(_ hook: (@Sendable () -> Void)?) {
        lock.withLock { _afterFetchHook = hook }
    }

    /// One entry per upcoming `deleteAllData` call, in order: how long that call waits before it
    /// runs (and before it checks the owner). `nil` means no wait.
    func setDeleteAllDataDelays(_ delays: [Duration?]) {
        lock.withLock { _deleteAllDataDelays = delays }
    }

    /// One entry per upcoming `setLike` call, in order. Calls after the list is used up succeed at once.
    func setSetLikeOutcomes(_ outcomes: [WriteOutcome]) {
        lock.withLock { _writeOutcomes["setLike"] = outcomes }
    }

    /// One entry per upcoming `removeLike` call, in order. Calls after the list is used up succeed at once.
    func setRemoveLikeOutcomes(_ outcomes: [WriteOutcome]) {
        lock.withLock { _writeOutcomes["removeLike"] = outcomes }
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
        let (likes, hook): ([Like], (@Sendable () -> Void)?) = try lock.withLock {
            if let error = _fetchError { throw error }
            let hook = _afterFetchHook
            _afterFetchHook = nil
            return (sorted(_likes[uid]), hook)
        }
        hook?()
        return likes
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
        try await applyNextOutcome(of: "setLike")
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
        try await applyNextOutcome(of: "removeLike")
        lock.withLock { _ = _likes[uid]?.removeValue(forKey: poemId) }
        notify(uid)
    }

    /// Waits and throws as the next queued outcome of `call` says; does nothing when none is queued.
    private func applyNextOutcome(of call: String) async throws {
        let outcome: WriteOutcome? = lock.withLock {
            guard var queued = _writeOutcomes[call], !queued.isEmpty else { return nil }
            let next = queued.removeFirst()
            _writeOutcomes[call] = queued
            return next
        }
        guard let outcome else { return }
        if let delay = outcome.delay { try await Task.sleep(for: delay) }
        if let error = outcome.error { throw error }
    }

    func ensureUserDocument(uid: String) async throws {
        try record("ensureUserDocument", uid: uid)
        lock.withLock {
            if _userDocuments[uid] == nil { _userDocuments[uid] = .now }
        }
    }

    /// Idempotent, like the real store: deleting data that is already gone succeeds.
    func deleteAllData(uid: String) async throws {
        let delay: Duration? = lock.withLock {
            _deleteAllDataDelays.isEmpty ? nil : _deleteAllDataDelays.removeFirst()
        }
        if let delay { try await Task.sleep(for: delay) }
        try record("deleteAllData", uid: uid)
        lock.withLock {
            _likes[uid] = nil
            _userDocuments[uid] = nil
        }
        notify(uid)
    }
}

/// In-memory `PhotoSubmissionStore`. `waiting` holds the records that exist, as "{authorId}_{uid}".
/// Records every call as "isWaiting 7_alice", "send 7_alice" or "delete 7_alice".
final class FakePhotoSubmissionStore: PhotoSubmissionStore, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var _calls: [String] = []
    private var _waiting: Set<String> = []
    private var _isWaitingError: Error?
    private var _sendError: Error?
    private var _deleteError: Error?
    private var _sendDelay: Duration?
    private var _isWaitingDelay: Duration?

    /// Every call to this fake, in order.
    var calls: [String] { lock.withLock { _calls } }

    /// The records that exist. A successful `send` adds one and a successful `delete` removes it.
    var waiting: Set<String> {
        get { lock.withLock { _waiting } }
        set { lock.withLock { _waiting = newValue } }
    }

    /// `isWaiting` throws this error until it is set back to nil.
    var isWaitingError: Error? {
        get { lock.withLock { _isWaitingError } }
        set { lock.withLock { _isWaitingError = newValue } }
    }

    /// `send` throws this error (after `sendDelay`) until it is set back to nil.
    var sendError: Error? {
        get { lock.withLock { _sendError } }
        set { lock.withLock { _sendError = newValue } }
    }

    /// `delete` throws this error until it is set back to nil.
    var deleteError: Error? {
        get { lock.withLock { _deleteError } }
        set { lock.withLock { _deleteError = newValue } }
    }

    /// `isWaiting` reads its answer, then waits this long before giving it, so tests can act while it is in flight.
    var isWaitingDelay: Duration? {
        get { lock.withLock { _isWaitingDelay } }
        set { lock.withLock { _isWaitingDelay = newValue } }
    }

    /// `send` waits this long after it is called, so tests can act while it is in flight.
    var sendDelay: Duration? {
        get { lock.withLock { _sendDelay } }
        set { lock.withLock { _sendDelay = newValue } }
    }

    private func key(_ authorId: Int, _ uid: String) -> String { "\(authorId)_\(uid)" }

    func isWaiting(authorId: Int, uid: String) async throws -> Bool {
        let key = key(authorId, uid)
        let (answer, delay): (Bool, Duration?) = try lock.withLock {
            _calls.append("isWaiting \(key)")
            if let error = _isWaitingError { throw error }
            return (_waiting.contains(key), _isWaitingDelay)
        }
        if let delay { try await Task.sleep(for: delay) }
        return answer
    }

    func send(_ jpeg: Data, authorId: Int, uid: String) async throws {
        let key = key(authorId, uid)
        let delay = lock.withLock {
            _calls.append("send \(key)")
            return _sendDelay
        }
        if let delay { try await Task.sleep(for: delay) }
        try lock.withLock {
            if let error = _sendError { throw error }
            _waiting.insert(key)
        }
    }

    func delete(authorId: Int, uid: String) async throws {
        let key = key(authorId, uid)
        try lock.withLock {
            _calls.append("delete \(key)")
            if let error = _deleteError { throw error }
            _waiting.remove(key)
        }
    }
}

/// Stands in for `PhotoSubmissions.deleteAll(uid:)` in `AccountManager` tests. Every call is recorded in the shared
/// `CallLog` as "deleteWaitingPhotos"; a uid is added to `deletedUids` only when the call succeeds.
final class FakePhotoDeleter: @unchecked Sendable {
    let log: CallLog
    private let lock = NSLock()
    private var _error: Error?
    private var _deletedUids: [String] = []

    init(log: CallLog = CallLog()) {
        self.log = log
    }

    /// `deleteAll` throws this error until it is set back to nil.
    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// The accounts whose waiting photos were deleted, in order.
    var deletedUids: [String] { lock.withLock { _deletedUids } }

    func deleteAll(uid: String) async throws {
        log.record("deleteWaitingPhotos")
        try lock.withLock {
            if let error = _error { throw error }
            _deletedUids.append(uid)
        }
    }
}

// MARK: - Daily picks

/// In-memory `DailyStore`. `documents` holds the `daily/{date}` documents that exist; a missing date fetches nil.
/// Records the date of every fetch, in order.
final class FakeDailyStore: DailyStore, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private var _documents: [String: DailyPicks] = [:]
    private var _error: Error?
    private var _fetches: [String] = []

    var documents: [String: DailyPicks] {
        get { lock.withLock { _documents } }
        set { lock.withLock { _documents = newValue } }
    }

    /// `fetch` throws this error until it is set back to nil.
    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// The date of every fetch, in call order.
    var fetches: [String] { lock.withLock { _fetches } }

    func fetch(date: String) async throws -> DailyPicks? {
        try lock.withLock {
            _fetches.append(date)
            if let _error { throw _error }
            return _documents[date]
        }
    }
}

// MARK: - Keep reading

/// In-memory `KeepReadingService`: answers every call with `result` and records the poem ID of each call.
final class FakeKeepReadingService: KeepReadingService, @unchecked Sendable {
    struct Unavailable: Error {}

    private let lock = NSLock()
    private let result: Result<KeepReading, Error>
    private var _calls: [Int] = []

    init(result: Result<KeepReading, Error>) {
        self.result = result
    }

    /// The poem ID of every call, in call order.
    var calls: [Int] { lock.withLock { _calls } }

    func suggestions(for poemId: Int) async throws -> KeepReading {
        try lock.withLock {
            _calls.append(poemId)
            return try result.get()
        }
    }
}

// MARK: - Reading history

/// In-memory `ReadsStore`. When `ownerUid` is given it acts like the security rules: every call for a uid other
/// than the signed-in one throws `PermissionDenied`. Writing a read that already exists succeeds, as the real
/// store treats the rules' refusal of a second create.
final class FakeReadsStore: ReadsStore, @unchecked Sendable {
    struct PermissionDenied: Error {}
    struct Failure: Error {}

    let log: CallLog
    private let ownerUid: (@Sendable () -> String?)?
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _reads: [String: Set<Int>] = [:]
    private var _markReadError: Error?
    private var _markReadHangs = false
    private var _fetchError: Error?
    private var _deleteError: Error?

    init(log: CallLog = CallLog(), ownerUid: (@Sendable () -> String?)? = nil) {
        self.log = log
        self.ownerUid = ownerUid
    }

    /// Every call to this fake, in order, as "markRead 7 alice", "enqueueRead 7 alice", "fetchReadIDs alice" or
    /// "deleteAllReads alice".
    var calls: [String] { lock.withLock { _calls } }

    func reads(for uid: String) -> Set<Int> {
        lock.withLock { _reads[uid] ?? [] }
    }

    /// Stores reads directly, without recording a call or checking the owner.
    func seed(_ ids: [Int], uid: String) {
        lock.withLock { _reads[uid, default: []].formUnion(ids) }
    }

    /// `markRead` throws this error until it is set back to nil.
    func setMarkReadError(_ error: Error?) {
        lock.withLock { _markReadError = error }
    }

    /// While true, `markRead` never answers, as a write does offline. Pair it with a test time limit.
    func setMarkReadHangs(_ hangs: Bool) {
        lock.withLock { _markReadHangs = hangs }
    }

    /// `fetchReadIDs` throws this error until it is set back to nil.
    func setFetchError(_ error: Error?) {
        lock.withLock { _fetchError = error }
    }

    /// `deleteAllReads` throws this error until it is set back to nil.
    func setDeleteError(_ error: Error?) {
        lock.withLock { _deleteError = error }
    }

    private func record(_ name: String, detail: String, uid: String) throws {
        lock.withLock { _calls.append("\(name) \(detail)") }
        log.record(name)
        if let ownerUid, ownerUid() != uid { throw PermissionDenied() }
    }

    func markRead(poemId: Int, uid: String) async throws {
        try record("markRead", detail: "\(poemId) \(uid)", uid: uid)
        if lock.withLock({ _markReadHangs }) { try await Task.sleep(for: .seconds(3600)) }
        try lock.withLock {
            if let _markReadError { throw _markReadError }
            _reads[uid, default: []].insert(poemId)
        }
    }

    /// Stores the read at once, as Firestore's local queue would; a refused write is dropped.
    func enqueueRead(poemId: Int, uid: String) {
        do {
            try record("enqueueRead", detail: "\(poemId) \(uid)", uid: uid)
        } catch {
            return
        }
        lock.withLock { _ = _reads[uid, default: []].insert(poemId) }
    }

    func fetchReadIDs(uid: String) async throws -> [Int] {
        try record("fetchReadIDs", detail: uid, uid: uid)
        return try lock.withLock {
            if let _fetchError { throw _fetchError }
            return (_reads[uid] ?? []).sorted()
        }
    }

    /// Idempotent, like the real store.
    func deleteAllReads(uid: String) async throws {
        try record("deleteAllReads", detail: uid, uid: uid)
        try lock.withLock {
            if let _deleteError { throw _deleteError }
            _reads[uid] = nil
        }
    }
}

/// A manual `Clock` for tests. Time moves only through `advance(by:)`, which wakes every sleeper whose deadline has
/// been reached. A sleep whose deadline has already passed returns at once; a cancelled sleep throws.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var _now = Instant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]

    var now: Instant { lock.withLock { _now } }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resumeNow: Result<Void, Error>? = lock.withLock {
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= _now { return .success(()) }
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let resumeNow { continuation.resume(with: resumeNow) }
            }
        } onCancel: {
            let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes the sleepers that are due.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            _now = _now.advanced(by: duration)
            let due = sleepers.filter { $0.value.deadline <= _now }
            for key in due.keys { sleepers[key] = nil }
            return Array(due.values)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

/// Lets main-actor work that was woken (e.g. by `TestClock.advance`) run to its next suspension, without real sleeps.
@MainActor
func settle() async {
    for _ in 0 ..< 50 { await Task.yield() }
}

// MARK: - Morning poem

/// In-memory `DeviceRegistry`. Every call is recorded in the shared `CallLog` as "upsertDevice" or "removeDevice",
/// and in `calls` with its install ID and uid. With `ownerUid`, a call for another uid is refused, as the rules do.
final class FakeDeviceRegistry: DeviceRegistry, @unchecked Sendable {
    struct PermissionDenied: Error {}
    struct Failure: Error {}

    let log: CallLog
    private let ownerUid: (@Sendable () -> String?)?
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _devices: [String: [String: DeviceRegistration]] = [:]
    private var _upsertError: Error?
    private var _removeError: Error?
    private var _removeHangs = false

    init(log: CallLog = CallLog(), ownerUid: (@Sendable () -> String?)? = nil) {
        self.log = log
        self.ownerUid = ownerUid
    }

    /// Every call, in order, as "upsert install-1 alice" or "remove install-1 alice".
    var calls: [String] { lock.withLock { _calls } }

    /// The device documents of `uid`, by install ID.
    func devices(for uid: String) -> [String: DeviceRegistration] {
        lock.withLock { _devices[uid] ?? [:] }
    }

    /// Stores a device directly, without recording a call or checking the owner.
    func seed(_ device: DeviceRegistration, installId: String, uid: String) {
        lock.withLock { _devices[uid, default: [:]][installId] = device }
    }

    /// `upsert` throws this error until it is set back to nil.
    func setUpsertError(_ error: Error?) {
        lock.withLock { _upsertError = error }
    }

    /// `remove` throws this error until it is set back to nil.
    func setRemoveError(_ error: Error?) {
        lock.withLock { _removeError = error }
    }

    /// While true, `remove` never answers, as a write does offline. Pair it with a test time limit.
    func setRemoveHangs(_ hangs: Bool) {
        lock.withLock { _removeHangs = hangs }
    }

    private func record(_ name: String, installId: String, uid: String) throws {
        lock.withLock { _calls.append("\(name) \(installId) \(uid)") }
        log.record(name + "Device")
        if let ownerUid, ownerUid() != uid { throw PermissionDenied() }
    }

    func upsert(_ device: DeviceRegistration, installId: String, uid: String) async throws {
        try record("upsert", installId: installId, uid: uid)
        try lock.withLock {
            if let _upsertError { throw _upsertError }
            _devices[uid, default: [:]][installId] = device
        }
    }

    /// Idempotent, like the real registry.
    func remove(installId: String, uid: String) async throws {
        try record("remove", installId: installId, uid: uid)
        if lock.withLock({ _removeHangs }) { try await Task.sleep(for: .seconds(3600)) }
        try lock.withLock {
            if let _removeError { throw _removeError }
            _devices[uid]?[installId] = nil
        }
    }

    /// Recorded as "removeAll <uid>" in `calls` and "removeAllDevices" in the log. Fails with the `remove` error.
    func removeAll(uid: String) async throws {
        lock.withLock { _calls.append("removeAll \(uid)") }
        log.record("removeAllDevices")
        if let ownerUid, ownerUid() != uid { throw PermissionDenied() }
        try lock.withLock {
            if let _removeError { throw _removeError }
            _devices[uid] = nil
        }
    }
}

/// A `NotificationPermission` whose system answer the test sets. While the status is not determined, `request()`
/// answers `granted` and moves the status to authorized or denied, as the system prompt does; after that it answers
/// from the status without asking again.
final class FakeNotificationPermission: NotificationPermission, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: UNAuthorizationStatus
    private let granted: Bool
    private var _requests = 0

    init(status: UNAuthorizationStatus = .notDetermined, granted: Bool = true) {
        _status = status
        self.granted = granted
    }

    /// How often `request()` was called.
    var requests: Int { lock.withLock { _requests } }

    func setStatus(_ status: UNAuthorizationStatus) {
        lock.withLock { _status = status }
    }

    func status() async -> UNAuthorizationStatus {
        lock.withLock { _status }
    }

    func request() async -> Bool {
        lock.withLock {
            _requests += 1
            if _status == .notDetermined { _status = granted ? .authorized : .denied }
            return _status == .authorized
        }
    }
}
