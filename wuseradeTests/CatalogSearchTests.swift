import Foundation
import Testing
@testable import Wuserade

struct CatalogSearchTests {
    private func summary(
        id: Int = 1,
        title: String,
        authorId: Int = 1,
        authorName: String = "Автор",
        themeId: Int? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> PoemSummary {
        PoemSummary(
            id: id,
            title: title,
            authorId: authorId,
            authorName: authorName,
            themeId: themeId,
            createdAt: createdAt
        )
    }

    @Test(arguments: ["КӀуэ", "Кlуэ", "К1уэ", "КIуэ", "кӏуэ"])
    func `Normalize maps palochka variants`(spelling: String) {
        #expect(CatalogSearch.normalize(spelling) == "кӏуэ")
    }

    @Test func `Normalize trims`() {
        #expect(CatalogSearch.normalize("  Псы ") == "псы")
    }

    @Test(arguments: ["   ", ""])
    func `Whitespace query returns nothing`(query: String) {
        let entries = [summary(title: "Псы цӀыкӀу")]
        #expect(CatalogSearch.search(query, in: entries).isEmpty)
    }

    @Test func `Matches title substring across palochka variants`() {
        let poem = summary(title: "ПСЫ ЦӀЫКӀУ")
        let result = CatalogSearch.search("цlык", in: [poem])
        #expect(result == [poem])
    }

    @Test func `Matches author name`() {
        let poem = summary(title: "Бзэ", authorName: "Агънокъуэ Лашэ")
        let other = summary(id: 2, title: "Хы", authorName: "Кущхьэ Алим")
        let result = CatalogSearch.search("лашэ", in: [poem, other])
        #expect(result == [poem])
    }

    @Test func `Title prefix ranks first`() {
        let prefix = summary(id: 1, title: "Псы цӀыкӀу")
        let infix = summary(id: 2, title: "Си псы")
        let result = CatalogSearch.search("псы", in: [infix, prefix])
        #expect(result.map(\.id) == [1, 2])
    }

    @Test func `Ranking groups title prefix then title then author ordered by title`() {
        let authorOnlyB = summary(id: 1, title: "Бзэ", authorName: "Псыкъуэ")
        let authorOnlyA = summary(id: 2, title: "Анэ", authorName: "Псыкъуэ")
        let titleInfix = summary(id: 3, title: "Си псы")
        let prefixB = summary(id: 4, title: "Псыбэ")
        let prefixA = summary(id: 5, title: "Псы")
        let result = CatalogSearch.search(
            "псы",
            in: [authorOnlyB, titleInfix, prefixB, authorOnlyA, prefixA]
        )
        #expect(result.map(\.id) == [5, 4, 3, 2, 1])
    }
}
