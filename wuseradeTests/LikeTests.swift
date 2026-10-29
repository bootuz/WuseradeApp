import Foundation
import Testing
import FirebaseFirestore
@testable import Wuserade

struct LikeTests {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_002_000)

    private func poem(_ id: Int) -> Poem {
        Poem(id: id, title: "Poem \(id)", author: Author(id: 10 + id, name: "Author \(id)"), content: "Text \(id)")
    }

    private func like(_ id: Int, at date: Date) -> Like {
        Like(poem: poem(id), likedAt: date)
    }

    @Test func `Merge keeps earliest and union`() {
        let merged = LikesMerge.merge(
            existing: [like(1, at: t2)],
            incoming: [like(1, at: t1), like(2, at: t3)]
        )
        #expect(merged == [like(2, at: t3), like(1, at: t1)])
    }

    @Test func `Merge keeps existing when it is earlier`() {
        let merged = LikesMerge.merge(
            existing: [like(1, at: t1), like(3, at: t3)],
            incoming: [like(1, at: t2)]
        )
        #expect(merged == [like(3, at: t3), like(1, at: t1)])
    }

    @Test func `Like encodes exactly rule fields`() throws {
        let encoded = try Firestore.Encoder().encode(like(7, at: t1))
        #expect(Set(encoded.keys) == ["poemId", "likedAt", "title", "authorId", "authorName", "text"])
        // The rules check the types too: `poemId`/`authorId` int, `likedAt` timestamp.
        #expect((encoded["poemId"] as? Int) == 7)
        #expect((encoded["authorId"] as? Int) == 17)
        #expect((encoded["likedAt"] as? Timestamp)?.dateValue() == t1)
    }

    @Test func `Like round trips poem`() throws {
        let original = poem(7)
        let like = Like(poem: original, likedAt: t1)
        #expect(like.id == 7)
        #expect(like.poem == original)

        let decoded = try Firestore.Decoder().decode(Like.self, from: Firestore.Encoder().encode(like))
        #expect(decoded == like)
        #expect(decoded.poem == original)
    }

    @Test func `Pending likes store saves loads and clears`() throws {
        let suiteName = "LikeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PendingLikesStore(defaults: defaults)

        #expect(store.load() == [])
        store.save([like(2, at: t3), like(1, at: t1)])
        #expect(PendingLikesStore(defaults: defaults).load() == [like(2, at: t3), like(1, at: t1)])
        store.clear()
        #expect(store.load() == [])
    }
}
