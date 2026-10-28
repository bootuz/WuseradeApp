import XCTest
@testable import Wuserade

final class ParsedPoemTests: XCTestCase {
    /// 'НАСЫП ЯМЫХЪУМА' in miniature: sections of one stanza each, split by '* * *'.
    func testLazyRowsKeepEverySectionInOrder() {
        let poem = ParsedPoem("Зы\nТӀу\n\n* * *\nЩы\nПлӀы\n\n* * *\nТху\n\nХы")
        let texts = poem.lazyRows.map { row -> [String] in
            if case .lines(let lines) = row { return lines.map(\.text) }
            return ["* * *"]
        }
        XCTAssertEqual(texts, [["Зы", "ТӀу"], ["* * *"], ["Щы", "ПлӀы"], ["* * *"], ["Тху"], ["Хы"]])
    }

    func testLazyRowsWithoutBreaksAreStanzas() {
        let poem = ParsedPoem("Зы\nТӀу\n\nЩы")
        XCTAssertEqual(poem.lazyRows.count, 2)
    }
}
