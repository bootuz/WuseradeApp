import XCTest
@testable import Wuserade

final class AuthorTests: XCTestCase {
    func testUnknownAuthor() {
        XCTAssertTrue(Author(id: 1, name: "Зытхар тщ\u{04C0}экъым").isUnknownAuthor)
        XCTAssertTrue(Author(id: 1, name: "Зытхар тщ\u{04CF}экъым").isUnknownAuthor)
        XCTAssertFalse(Author(id: 7, name: "Author 7").isUnknownAuthor)
    }
}
