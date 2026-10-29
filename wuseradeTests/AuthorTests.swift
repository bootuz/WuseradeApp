import Testing
@testable import Wuserade

struct AuthorTests {
    @Test func `Unknown author`() {
        #expect(Author(id: 1, name: "Зытхар тщ\u{04C0}экъым").isUnknownAuthor)
        #expect(Author(id: 1, name: "Зытхар тщ\u{04CF}экъым").isUnknownAuthor)
        #expect(!Author(id: 7, name: "Author 7").isUnknownAuthor)
    }
}
