import XCTest
@testable import Wuserade

final class CatalogSearchTests: XCTestCase {
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

    func testNormalizeMapsPalochkaVariants() {
        let expected = "кӏуэ"
        XCTAssertEqual(CatalogSearch.normalize("КӀуэ"), expected)
        XCTAssertEqual(CatalogSearch.normalize("Кlуэ"), expected)
        XCTAssertEqual(CatalogSearch.normalize("К1уэ"), expected)
        XCTAssertEqual(CatalogSearch.normalize("КIуэ"), expected)
        XCTAssertEqual(CatalogSearch.normalize("кӏуэ"), expected)
    }

    func testNormalizeTrims() {
        XCTAssertEqual(CatalogSearch.normalize("  Псы "), "псы")
    }

    func testWhitespaceQueryReturnsNothing() {
        let entries = [summary(title: "Псы цӀыкӀу")]
        XCTAssertTrue(CatalogSearch.search("   ", in: entries).isEmpty)
        XCTAssertTrue(CatalogSearch.search("", in: entries).isEmpty)
    }

    func testMatchesTitleSubstringAcrossPalochkaVariants() {
        let poem = summary(title: "ПСЫ ЦӀЫКӀУ")
        let result = CatalogSearch.search("цlык", in: [poem])
        XCTAssertEqual(result, [poem])
    }

    func testMatchesAuthorName() {
        let poem = summary(title: "Бзэ", authorName: "Агънокъуэ Лашэ")
        let other = summary(id: 2, title: "Хы", authorName: "Кущхьэ Алим")
        let result = CatalogSearch.search("лашэ", in: [poem, other])
        XCTAssertEqual(result, [poem])
    }

    func testTitlePrefixRanksFirst() {
        let prefix = summary(id: 1, title: "Псы цӀыкӀу")
        let infix = summary(id: 2, title: "Си псы")
        let result = CatalogSearch.search("псы", in: [infix, prefix])
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testRankingGroupsTitlePrefixThenTitleThenAuthorOrderedByTitle() {
        let authorOnlyB = summary(id: 1, title: "Бзэ", authorName: "Псыкъуэ")
        let authorOnlyA = summary(id: 2, title: "Анэ", authorName: "Псыкъуэ")
        let titleInfix = summary(id: 3, title: "Си псы")
        let prefixB = summary(id: 4, title: "Псыбэ")
        let prefixA = summary(id: 5, title: "Псы")
        let result = CatalogSearch.search(
            "псы",
            in: [authorOnlyB, titleInfix, prefixB, authorOnlyA, prefixA]
        )
        XCTAssertEqual(result.map(\.id), [5, 4, 3, 2, 1])
    }
}
