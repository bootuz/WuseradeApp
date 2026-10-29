import XCTest
@testable import Wuserade

final class AuthorEntryTests: XCTestCase {
    private func decodeEntry(_ json: String) throws -> AuthorEntry {
        try JSONDecoder().decode(AuthorEntry.self, from: Data(json.utf8))
    }

    func testDecodesPhotoURL() throws {
        let entry = try decodeEntry(#"{"id":7,"name":"А","poemsCount":3,"photoURL":"https://x/7.jpg"}"#)

        XCTAssertEqual(entry.photoURL, "https://x/7.jpg")
    }

    func testMissingOrNullPhotoURLIsNil() throws {
        let missing = try decodeEntry(#"{"id":7,"name":"А","poemsCount":3}"#)
        let null = try decodeEntry(#"{"id":7,"name":"А","poemsCount":3,"photoURL":null}"#)

        XCTAssertNil(missing.photoURL)
        XCTAssertNil(null.photoURL)
    }

    /// `meta/content` as an older build saved it in the on-disk cache, before authors could carry a photo.
    func testCachedMetaWithoutPhotosStillDecodes() throws {
        let json = """
        {"catalogVersion":3,"catalogChunks":2,
         "authors":[{"id":4,"name":"Лашэ","poemsCount":12},{"id":7,"name":"Бемырзэ","poemsCount":3}],
         "themes":[{"id":9,"title":"Хы"}],"nextPoemId":100}
        """

        let meta = try JSONDecoder().decode(ContentMeta.self, from: Data(json.utf8))

        XCTAssertEqual(meta.authors.map(\.id), [4, 7])
        XCTAssertEqual(meta.authors.map(\.photoURL), [nil, nil])
        XCTAssertEqual(meta.themes, [Wuserade.Category(id: 9, title: "Хы")])
    }
}
