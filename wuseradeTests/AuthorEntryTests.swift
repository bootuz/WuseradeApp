import Foundation
import Testing
@testable import Wuserade

struct AuthorEntryTests {
    private func decodeEntry(_ json: String) throws -> AuthorEntry {
        try JSONDecoder().decode(AuthorEntry.self, from: Data(json.utf8))
    }

    @Test func `Decodes photo URL`() throws {
        let entry = try decodeEntry(#"{"id":7,"name":"А","poemsCount":3,"photoURL":"https://x/7.jpg"}"#)

        #expect(entry.photoURL == "https://x/7.jpg")
    }

    @Test(arguments: [
        #"{"id":7,"name":"А","poemsCount":3}"#,
        #"{"id":7,"name":"А","poemsCount":3,"photoURL":null}"#,
    ])
    func `Missing or null photo URL is nil`(json: String) throws {
        let entry = try decodeEntry(json)

        #expect(entry.photoURL == nil)
    }

    /// `meta/content` as an older build saved it in the on-disk cache, before authors could carry a photo.
    @Test func `Cached meta without photos still decodes`() throws {
        let json = """
        {"catalogVersion":3,"catalogChunks":2,
         "authors":[{"id":4,"name":"Лашэ","poemsCount":12},{"id":7,"name":"Бемырзэ","poemsCount":3}],
         "themes":[{"id":9,"title":"Хы"}],"nextPoemId":100}
        """

        let meta = try JSONDecoder().decode(ContentMeta.self, from: Data(json.utf8))

        #expect(meta.authors.map(\.id) == [4, 7])
        #expect(meta.authors.map(\.photoURL) == [nil, nil])
        #expect(meta.themes == [Wuserade.Category(id: 9, title: "Хы")])
    }
}
