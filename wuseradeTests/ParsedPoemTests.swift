import Testing
@testable import Wuserade

struct ParsedPoemTests {
    /// 'НАСЫП ЯМЫХЪУМА' in miniature: sections of one stanza each, split by '* * *'.
    @Test func `Lazy rows keep every section in order`() {
        let poem = ParsedPoem("Зы\nТӀу\n\n* * *\nЩы\nПлӀы\n\n* * *\nТху\n\nХы")
        let texts = poem.lazyRows.map { row -> [String] in
            if case .lines(let lines) = row { return lines.map(\.text) }
            return ["* * *"]
        }
        #expect(texts == [["Зы", "ТӀу"], ["* * *"], ["Щы", "ПлӀы"], ["* * *"], ["Тху"], ["Хы"]])
    }

    @Test func `Lazy rows without breaks are stanzas`() {
        let poem = ParsedPoem("Зы\nТӀу\n\nЩы")
        #expect(poem.lazyRows.count == 2)
    }
}
