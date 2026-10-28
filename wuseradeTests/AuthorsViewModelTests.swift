import XCTest
@testable import Wuserade

final class AuthorsViewModelTests: XCTestCase {
    private func authors(_ names: [String]) -> [Author] {
        names.enumerated().map { Author(id: $0.offset + 1, name: $0.element) }
    }

    func testGroupsByKabardianAlphabet() {
        let groups = AuthorsViewModel().grouped(authors(["Хьэбэч", "Агънокъуэ Лашэ", "Бэчыжь", "Апажэ"]))

        XCTAssertEqual(groups.map(\.key), ["а", "б", "хь"])
        XCTAssertEqual(groups[0].value.map(\.name), ["Агънокъуэ Лашэ", "Апажэ"])
        XCTAssertEqual(groups[1].value.map(\.name), ["Бэчыжь"])
        XCTAssertEqual(groups[2].value.map(\.name), ["Хьэбэч"])
    }

    /// In the Kabardian alphabet "э" comes right after "а", unlike Unicode order where it sorts near the end.
    func testUsesKabardianOrderNotUnicodeOrder() {
        let groups = AuthorsViewModel().grouped(authors(["Бэчыжь", "Эуэз", "Абаз"]))

        XCTAssertEqual(groups.map(\.key), ["а", "э", "б"])
    }

    func testNoAuthorsGivesNoGroups() {
        XCTAssertTrue(AuthorsViewModel().grouped([]).isEmpty)
    }
}
