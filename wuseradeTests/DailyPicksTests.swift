import Foundation
import Testing
import FirebaseFirestore
@testable import Wuserade

struct DailyPicksTests {
    private func poemFields(id: Int, title: String, text: String) -> [String: Any] {
        ["id": id, "title": title, "authorId": 12, "authorName": "Author 12", "text": text]
    }

    @Test func `Decodes the server document`() throws {
        let fields: [String: Any] = [
            "date": "2026-10-29",
            "poem": poemFields(id: 4130, title: "Гъатхэ", text: "One\nTwo"),
            "shortPoem": poemFields(id: 77, title: "", text: "Short,\nverse"),
            "poet": [
                "id": 12,
                "name": "Author 12",
                "poemsCount": 452,
                "topPoems": [["id": 1, "title": "First"], ["id": 2, "title": "Second"]] as [[String: Any]],
            ] as [String: Any],
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_800_000_000)),
        ]

        let picks = try FirestoreDailyStore.picks(from: fields)

        #expect(picks.date == "2026-10-29")
        #expect(picks.poem.id == 4130)
        #expect(picks.poem.poem == Poem(id: 4130, title: "Гъатхэ", author: Author(id: 12, name: "Author 12"), content: "One\nTwo"))
        #expect(picks.shortPoem.id == 77)
        #expect(picks.poet.photoURL == nil)
        #expect(picks.poet.poemsCount == 452)
        #expect(picks.poet.topPoems == [DailyPoemRef(id: 1, title: "First"), DailyPoemRef(id: 2, title: "Second")])
        #expect(picks.poet.author == Author(id: 12, name: "Author 12"))
    }

    @Test func `Decodes the REST document`() throws {
        let json = """
        {
          "name": "projects/wuserade/databases/(default)/documents/daily/2026-10-29",
          "fields": {
            "date": { "stringValue": "2026-10-29" },
            "poem": { "mapValue": { "fields": {
              "id": { "integerValue": "4130" },
              "title": { "stringValue": "Title" },
              "authorId": { "integerValue": "12" },
              "authorName": { "stringValue": "Author 12" },
              "text": { "stringValue": "One\\nTwo" }
            } } },
            "shortPoem": { "mapValue": { "fields": {
              "id": { "integerValue": "77" },
              "title": { "stringValue": "" },
              "authorId": { "integerValue": "5" },
              "authorName": { "stringValue": "Author 5" },
              "text": { "stringValue": "Short" }
            } } },
            "poet": { "mapValue": { "fields": {
              "id": { "integerValue": "12" },
              "name": { "stringValue": "Author 12" },
              "poemsCount": { "integerValue": "452" },
              "photoURL": { "stringValue": "https://x/12.jpg" },
              "topPoems": { "arrayValue": { "values": [
                { "mapValue": { "fields": { "id": { "integerValue": "1" }, "title": { "stringValue": "First" } } } },
                { "mapValue": { "fields": { "id": { "integerValue": "2" }, "title": { "stringValue": "Second" } } } }
              ] } }
            } } },
            "createdAt": { "timestampValue": "2026-10-22T03:00:00.123456Z" }
          },
          "createTime": "2026-10-22T03:00:00.123456Z",
          "updateTime": "2026-10-22T03:00:00.123456Z"
        }
        """

        let picks = try FirestoreREST.decode(DailyPicks.self, from: Data(json.utf8))

        #expect(picks.date == "2026-10-29")
        #expect(picks.poem.id == 4130)
        #expect(picks.poem.text == "One\nTwo")
        #expect(picks.shortPoem.authorId == 5)
        #expect(picks.poet.poemsCount == 452)
        #expect(picks.poet.photoURL == "https://x/12.jpg")
        #expect(picks.poet.topPoems.map(\.id) == [1, 2])
    }

    @Test func `REST values unwrap booleans, nulls and empty containers`() throws {
        struct Sample: Decodable, Equatable {
            let flag: Bool
            let missing: String?
            let empty: [Int]
            let nested: [String: Int]
        }
        let json = """
        { "fields": {
            "flag": { "booleanValue": true },
            "missing": { "nullValue": null },
            "empty": { "arrayValue": {} },
            "nested": { "mapValue": {} }
        } }
        """
        let sample = try FirestoreREST.decode(Sample.self, from: Data(json.utf8))
        #expect(sample == Sample(flag: true, missing: nil, empty: [], nested: [:]))
    }

    @Test func `untitledDailyPoemUsesFirstLine`() {
        let poem = DailyPoem(id: 1, title: "", authorId: 2, authorName: "Author 2", text: "Line one,\nLine two")
        #expect(poem.summary.firstLine == "Line one")
        #expect(poem.summary.isUntitled)
        #expect(poem.summary.id == 1)
    }

    @Test func `DailyDate uses the local calendar day`() throws {
        let date = try Date("2026-10-29T22:30:00Z", strategy: .iso8601)
        let moscow = try #require(TimeZone(identifier: "Europe/Moscow"))
        #expect(DailyDate.string(for: date, in: moscow) == "2026-10-30")
        #expect(DailyDate.string(for: date, in: try #require(TimeZone(identifier: "UTC"))) == "2026-10-29")
    }
}
