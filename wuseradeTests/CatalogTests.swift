import Foundation
import Testing
import FirebaseFirestore
@testable import Wuserade

struct CatalogTests {
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

    @Test func `Newest first`() {
        let catalog = Catalog(version: 1, entries: [
            summary(id: 1, daysAgo: 3),
            summary(id: 2, daysAgo: 1),
            summary(id: 3, daysAgo: 2),
        ])
        #expect(catalog.newestFirst().map(\.id) == [2, 3, 1])
    }

    @Test func `Poems by author filters`() {
        let catalog = Catalog(version: 1, entries: [
            summary(id: 1, authorId: 10, daysAgo: 3),
            summary(id: 2, authorId: 20, daysAgo: 1),
            summary(id: 3, authorId: 10, daysAgo: 2),
        ])
        #expect(catalog.poems(byAuthor: 10).map(\.id) == [3, 1])
        #expect(catalog.poems(byAuthor: 99).isEmpty)
    }

    @Test func `Poems in theme excludes nil`() {
        let catalog = Catalog(version: 1, entries: [
            summary(id: 1, themeId: 5, daysAgo: 3),
            summary(id: 2, themeId: nil, daysAgo: 1),
            summary(id: 3, themeId: 5, daysAgo: 2),
            summary(id: 4, themeId: 6, daysAgo: 0),
        ])
        #expect(catalog.poems(inTheme: 5).map(\.id) == [3, 1])
    }

    @Test func `Chunk decodes from Firestore data`() throws {
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
        #expect(chunk.version == 3)
        #expect(chunk.entries.count == 1)
        #expect(chunk.entries[0].themeId == nil)
        #expect(chunk.entries[0].createdAt == date)
        #expect(chunk.entries[0].author == Author(id: 2, name: "a"))
    }

    @Test func `Content meta decodes from Firestore data`() throws {
        let data: [String: Any] = [
            "catalogVersion": 7,
            "catalogChunks": 2,
            "authors": [["id": 4, "name": "Лашэ", "poemsCount": 12] as [String: Any]],
            "themes": [["id": 9, "title": "Хы", "poemsCount": 3] as [String: Any]],
            "nextPoemId": 101,
            "minimumAppVersion": NSNull(),
        ]
        let meta = try Firestore.Decoder().decode(ContentMeta.self, from: data)
        #expect(meta.catalogVersion == 7)
        #expect(meta.catalogChunks == 2)
        #expect(meta.authors == [AuthorEntry(id: 4, name: "Лашэ", poemsCount: 12)])
        #expect(meta.authors[0].author == Author(id: 4, name: "Лашэ"))
        #expect(meta.themes == [Category(id: 9, title: "Хы")])
        #expect(meta.nextPoemId == 101)
    }

    // MARK: meta/content as read by FirestoreContentRepository

    private let metaFields: [String: Any] = [
        "catalogVersion": 7,
        "catalogChunks": 2,
        "authors": [["id": 4, "name": "Лашэ", "poemsCount": 12] as [String: Any]],
        "themes": [["id": 9, "title": "Хы", "poemsCount": 3] as [String: Any]],
        "nextPoemId": 101,
    ]

    @Test func `Meta document reads minimum app version with the rest`() throws {
        var fields = metaFields
        fields["minimumAppVersion"] = "1.5"
        let document = MetaDocument(fields: fields)
        #expect(document.minimumAppVersion == "1.5")
        #expect(try document.meta.get().catalogVersion == 7)
    }

    /// A later `meta/content` this build cannot decode must still tell it to update.
    @Test func `Meta document reads minimum app version when the rest does not decode`() {
        let document = MetaDocument(fields: [
            "catalogVersion": "eight",
            "catalogChunks": ["count": 3],
            "minimumAppVersion": "2.0",
        ])
        #expect(document.minimumAppVersion == "2.0")
        #expect(throws: (any Error).self) { try document.meta.get() }
    }

    @Test func `Meta document minimum app version is nil when missing null or not a string`() throws {
        #expect(MetaDocument(fields: metaFields).minimumAppVersion == nil)
        for value: Any in [NSNull(), 2, ["1.5"]] {
            var fields = metaFields
            fields["minimumAppVersion"] = value
            let document = MetaDocument(fields: fields)
            #expect(document.minimumAppVersion == nil, "\(value)")
            #expect(try document.meta.get().catalogVersion == 7)
        }
    }
}
