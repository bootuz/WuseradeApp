import Foundation
import Testing
@testable import Wuserade

struct KeepReadingTests {
    private let poet = Author(id: 12, name: "Author 12")
    private let next = PoemSummary(id: 9, title: "Next", authorId: 3, authorName: "Author 3", themeId: 1, createdAt: .distantPast)
    private let suggestions = KeepReading(
        poet: [KeepReading.Ref(id: 1, title: "First")],
        similar: [KeepReading.Similar(id: 2, title: "Second", authorId: 5, authorName: "Author 5")]
    )

    @Test func `Decodes the callable result`() throws {
        // What the Functions SDK hands back: the JSON result as Foundation objects, numbers as NSNumber.
        let data: Any = [
            "poet": [["id": NSNumber(value: 1), "title": "First"], ["id": NSNumber(value: 3), "title": ""]],
            "similar": [["id": NSNumber(value: 2), "title": "Second", "authorId": NSNumber(value: 5), "authorName": "Author 5"]],
        ] as [String: Any]

        let decoded = try FirebaseKeepReadingService.decode(data)

        #expect(decoded == KeepReading(
            poet: [KeepReading.Ref(id: 1, title: "First"), KeepReading.Ref(id: 3, title: "")],
            similar: [KeepReading.Similar(id: 2, title: "Second", authorId: 5, authorName: "Author 5")]
        ))
    }

    @Test func `Poet rows carry the reader's poet`() {
        let poetRows = suggestions.poetSummaries(author: poet)
        let similarRows = suggestions.similarSummaries

        #expect(poetRows == [PoemSummary(id: 1, title: "First", authorId: 12, authorName: "Author 12", themeId: nil, createdAt: .distantPast)])
        #expect(similarRows == [PoemSummary(id: 2, title: "Second", authorId: 5, authorName: "Author 5", themeId: nil, createdAt: .distantPast)])
    }

    @Test func `Suggestions replace the next row`() async {
        let service = FakeKeepReadingService(result: .success(suggestions))

        let result = await KeepReadingState.load(9, from: service)

        #expect(service.calls == [9])
        #expect(KeepReadingState.resolve(result: result, next: next) == .suggestions(suggestions))
    }

    @Test func `Empty result keeps the next row`() async {
        let service = FakeKeepReadingService(result: .success(KeepReading(poet: [], similar: [])))

        let result = await KeepReadingState.load(9, from: service)

        #expect(KeepReadingState.resolve(result: result, next: next) == .next(next))
        #expect(KeepReadingState.resolve(result: result, next: nil) == .nothing)
    }

    @Test func `Failure keeps the next row`() async {
        let service = FakeKeepReadingService(result: .failure(FakeKeepReadingService.Unavailable()))

        let result = await KeepReadingState.load(9, from: service)

        #expect(KeepReadingState.resolve(result: result, next: next) == .next(next))
        #expect(KeepReadingState.resolve(result: result, next: nil) == .nothing)
    }

    @Test func `The next row shows while suggestions load`() {
        #expect(KeepReadingState.resolve(result: nil, next: next) == .next(next))
        #expect(KeepReadingState.resolve(result: nil, next: nil) == .nothing)
    }

    // MARK: When a page asks

    @Test func `A page that is not being read does not ask`() {
        #expect(!KeepReadingState.shouldLoad(shown: false, endTop: 100, scrollHeight: 800, cached: false))
        #expect(!KeepReadingState.shouldLoad(shown: false, endTop: 3000, scrollHeight: 800, cached: false))
    }

    @Test func `The page being read waits until its end is about a screen away`() {
        #expect(!KeepReadingState.shouldLoad(shown: true, endTop: 2400, scrollHeight: 800, cached: false))
        #expect(!KeepReadingState.shouldLoad(shown: true, endTop: 1600, scrollHeight: 800, cached: false))
        #expect(KeepReadingState.shouldLoad(shown: true, endTop: 1599, scrollHeight: 800, cached: false))
    }

    @Test func `A short poem asks at once`() {
        #expect(KeepReadingState.shouldLoad(shown: true, endTop: 500, scrollHeight: 800, cached: false))
    }

    @Test func `Nothing is asked before the page is measured`() {
        #expect(!KeepReadingState.shouldLoad(shown: true, endTop: .greatestFiniteMagnitude, scrollHeight: 0, cached: false))
    }

    @Test func `Kept suggestions are not asked for again`() {
        #expect(!KeepReadingState.shouldLoad(shown: true, endTop: 500, scrollHeight: 800, cached: true))
    }

    // MARK: Kept in the pager

    @MainActor
    @Test func `A rebuilt page reuses the pager's suggestions`() async {
        let pager = ReaderPager()
        let service = FakeKeepReadingService(result: .success(suggestions))
        pager.bindSuggestions(uid: "u1")

        await pager.loadSuggestions(9, from: service)
        await pager.loadSuggestions(9, from: service)

        #expect(service.calls == [9])
        #expect(pager.suggestions[9] == suggestions)
    }

    @MainActor
    @Test func `A failure is not kept, so the poem asks again next time`() async {
        let pager = ReaderPager()
        let service = FakeKeepReadingService(result: .failure(FakeKeepReadingService.Unavailable()))
        pager.bindSuggestions(uid: "u1")

        await pager.loadSuggestions(9, from: service)
        await pager.loadSuggestions(9, from: service)

        #expect(service.calls == [9, 9])
        #expect(pager.suggestions[9] == nil)
    }

    @MainActor
    @Test func `Another account forgets the suggestions`() async {
        let pager = ReaderPager()
        let service = FakeKeepReadingService(result: .success(suggestions))
        pager.bindSuggestions(uid: "u1")
        await pager.loadSuggestions(9, from: service)

        pager.bindSuggestions(uid: "u1")
        #expect(pager.suggestions[9] == suggestions, "the same account keeps them")

        pager.bindSuggestions(uid: "u2")
        #expect(pager.suggestions[9] == nil)
        await pager.loadSuggestions(9, from: service)
        #expect(service.calls == [9, 9])
    }
}
