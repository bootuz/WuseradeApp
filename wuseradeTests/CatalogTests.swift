import XCTest
import FirebaseFirestore
@testable import Wuserade

final class CatalogTests: XCTestCase {
    private func summary(
        id: Int,
        authorId: Int = 1,
        themeId: Int? = nil,
        daysAgo: Int
    ) -> PoemSummary {
        PoemSummary(
            id: id,
            title: "Poem \(id)",
            authorId: authorId,
            authorName: "Author \(authorId)",
            themeId: themeId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400)
        )
    }

    func testNewestFirst() {
        let catalog = Catalog(version: 1, entries: [
            summary(id: 1, daysAgo: 3),
            summary(id: 2, daysAgo: 1),
            summary(id: 3, daysAgo: 2),
        ])
        XCTAssertEqual(catalog.newestFirst().map(\.id), [2, 3, 1])
    }

    func testPoemsByAuthorFilters() {
        let catalog = Catalog(version: 1, entries: [
            summary(id: 1, authorId: 10, daysAgo: 3),
            summary(id: 2, authorId: 20, daysAgo: 1),
            summary(id: 3, authorId: 10, daysAgo: 2),
        ])
        XCTAssertEqual(catalog.poems(byAuthor: 10).map(\.id), [3, 1])
        XCTAssertTrue(catalog.poems(byAuthor: 99).isEmpty)
    }

    func testPoemsInThemeExcludesNil() {
        let catalog = Catalog(version: 1, entries: [
            summary(id: 1, themeId: 5, daysAgo: 3),
            summary(id: 2, themeId: nil, daysAgo: 1),
            summary(id: 3, themeId: 5, daysAgo: 2),
            summary(id: 4, themeId: 6, daysAgo: 0),
        ])
        XCTAssertEqual(catalog.poems(inTheme: 5).map(\.id), [3, 1])
    }

    func testChunkDecodesFromFirestoreData() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data: [String: Any] = [
            "version": 3,
            "entries": [
                [
                    "id": 1,
                    "title": "t",
                    "authorId": 2,
                    "authorName": "a",
                    "themeId": NSNull(),
                    "createdAt": Timestamp(date: date),
                ] as [String: Any]
            ],
        ]
        let chunk = try Firestore.Decoder().decode(CatalogChunk.self, from: data)
        XCTAssertEqual(chunk.version, 3)
        XCTAssertEqual(chunk.entries.count, 1)
        XCTAssertNil(chunk.entries[0].themeId)
        XCTAssertEqual(chunk.entries[0].createdAt, date)
        XCTAssertEqual(chunk.entries[0].author, Author(id: 2, name: "a"))
    }

    func testContentMetaDecodesFromFirestoreData() throws {
        let data: [String: Any] = [
            "catalogVersion": 7,
            "catalogChunks": 2,
            "authors": [["id": 4, "name": "Лашэ", "poemsCount": 12] as [String: Any]],
            "themes": [["id": 9, "title": "Хы", "poemsCount": 3] as [String: Any]],
            "nextPoemId": 101,
            "minimumAppVersion": NSNull(),
        ]
        let meta = try Firestore.Decoder().decode(ContentMeta.self, from: data)
        XCTAssertEqual(meta.catalogVersion, 7)
        XCTAssertEqual(meta.catalogChunks, 2)
        XCTAssertEqual(meta.authors, [AuthorEntry(id: 4, name: "Лашэ", poemsCount: 12)])
        XCTAssertEqual(meta.authors[0].author, Author(id: 4, name: "Лашэ"))
        XCTAssertEqual(meta.themes, [Category(id: 9, title: "Хы")])
        XCTAssertEqual(meta.nextPoemId, 101)
    }

    // MARK: meta/content as read by FirestoreContentRepository

    private let metaFields: [String: Any] = [
        "catalogVersion": 7,
        "catalogChunks": 2,
        "authors": [["id": 4, "name": "Лашэ", "poemsCount": 12] as [String: Any]],
        "themes": [["id": 9, "title": "Хы", "poemsCount": 3] as [String: Any]],
        "nextPoemId": 101,
    ]

    func testMetaDocumentReadsMinimumAppVersionWithTheRest() throws {
        var fields = metaFields
        fields["minimumAppVersion"] = "1.5"
        let document = MetaDocument(fields: fields)
        XCTAssertEqual(document.minimumAppVersion, "1.5")
        XCTAssertEqual(try document.meta.get().catalogVersion, 7)
    }

    /// A later `meta/content` this build cannot decode must still tell it to update.
    func testMetaDocumentReadsMinimumAppVersionWhenTheRestDoesNotDecode() {
        let document = MetaDocument(fields: [
            "catalogVersion": "eight",
            "catalogChunks": ["count": 3],
            "minimumAppVersion": "2.0",
        ])
        XCTAssertEqual(document.minimumAppVersion, "2.0")
        XCTAssertThrowsError(try document.meta.get())
    }

    func testMetaDocumentMinimumAppVersionIsNilWhenMissingNullOrNotAString() throws {
        XCTAssertNil(MetaDocument(fields: metaFields).minimumAppVersion)
        for value: Any in [NSNull(), 2, ["1.5"]] {
            var fields = metaFields
            fields["minimumAppVersion"] = value
            let document = MetaDocument(fields: fields)
            XCTAssertNil(document.minimumAppVersion, "\(value)")
            XCTAssertEqual(try document.meta.get().catalogVersion, 7)
        }
    }
}
