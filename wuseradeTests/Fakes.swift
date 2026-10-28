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
