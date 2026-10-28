import XCTest
import FirebaseFirestore
@testable import Wuserade

final class LikeTests: XCTestCase {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_001_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_002_000)

    private func poem(_ id: Int) -> Poem {
        Poem(id: id, title: "Poem \(id)", author: Author(id: 10 + id, name: "Author \(id)"), content: "Text \(id)")
    }

    private func like(_ id: Int, at date: Date) -> Like {
        Like(poem: poem(id), likedAt: date)
    }

    func testMergeKeepsEarliestAndUnion() {
        let merged = LikesMerge.merge(
            existing: [like(1, at: t2)],
            incoming: [like(1, at: t1), like(2, at: t3)]
        )
        XCTAssertEqual(merged, [like(2, at: t3), like(1, at: t1)])
    }

    func testMergeKeepsExistingWhenItIsEarlier() {
        let merged = LikesMerge.merge(
            existing: [like(1, at: t1), like(3, at: t3)],
            incoming: [like(1, at: t2)]
        )
        XCTAssertEqual(merged, [like(3, at: t3), like(1, at: t1)])
    }

    func testLikeEncodesExactlyRuleFields() throws {
        let encoded = try Firestore.Encoder().encode(like(7, at: t1))
        XCTAssertEqual(
            Set(encoded.keys),
            ["poemId", "likedAt", "title", "authorId", "authorName", "text"]
        )
        // The rules check the types too: `poemId`/`authorId` int, `likedAt` timestamp.
        XCTAssertEqual(encoded["poemId"] as? Int, 7)
        XCTAssertEqual(encoded["authorId"] as? Int, 17)
        XCTAssertEqual((encoded["likedAt"] as? Timestamp)?.dateValue(), t1)
    }

    func testLikeRoundTripsPoem() throws {
        let original = poem(7)
        let like = Like(poem: original, likedAt: t1)
        XCTAssertEqual(like.id, 7)
        XCTAssertEqual(like.poem, original)

        let decoded = try Firestore.Decoder().decode(Like.self, from: Firestore.Encoder().encode(like))
        XCTAssertEqual(decoded, like)
        XCTAssertEqual(decoded.poem, original)
    }

    func testPendingLikesStoreSavesLoadsAndClears() throws {
        let suiteName = "LikeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PendingLikesStore(defaults: defaults)

        XCTAssertEqual(store.load(), [])
        store.save([like(2, at: t3), like(1, at: t1)])
        XCTAssertEqual(PendingLikesStore(defaults: defaults).load(), [like(2, at: t3), like(1, at: t1)])
        store.clear()
        XCTAssertEqual(store.load(), [])
    }
}
