import XCTest
@testable import Wuserade

@MainActor
final class PoemViewModelTests: XCTestCase {
    private let poem = Poem(
        id: 42,
        title: "Гъатхэ",
        author: Author(id: 7, name: "Усакlуэ"),
        content: "Гъатхэр къэсащ"
    )

    func testLoadsPoemFromRepository() async {
        let fake = FakeContentRepository(poems: [poem])
        let viewModel = PoemViewModel(repository: fake)
        XCTAssertNil(viewModel.poem)

        await viewModel.load(id: 42)

        XCTAssertEqual(viewModel.poem, poem)
        XCTAssertFalse(viewModel.loadFailed)
        XCTAssertEqual(fake.poemCalls, [42])
    }

    func testFailureSetsLoadFailed() async {
        let fake = FakeContentRepository(poems: [poem])
        fake.setOffline(true)
        let viewModel = PoemViewModel(repository: fake)

        await viewModel.load(id: 42)

        XCTAssertNil(viewModel.poem)
        XCTAssertTrue(viewModel.loadFailed)
        XCTAssertEqual(fake.poemCalls, [42])
    }

    func testPreloadedPoemSkipsRepository() async {
        let fake = FakeContentRepository(poems: [poem])
        let viewModel = PoemViewModel(repository: fake, preloaded: poem)

        // Shown at once, before any load.
        XCTAssertEqual(viewModel.poem, poem)

        await viewModel.load(id: 42)

        XCTAssertEqual(viewModel.poem, poem)
        XCTAssertFalse(viewModel.loadFailed)
        XCTAssertEqual(fake.poemCalls, [], "A preloaded poem must not hit the repository")
    }

    func testRetryAfterFailureLoadsPoemAndClearsLoadFailed() async {
        let fake = FakeContentRepository(poems: [poem])
        fake.setOffline(true)
        let viewModel = PoemViewModel(repository: fake)
        await viewModel.load(id: 42)
        XCTAssertTrue(viewModel.loadFailed)

        fake.setOffline(false)
        await viewModel.load(id: 42)

        XCTAssertEqual(viewModel.poem, poem)
        XCTAssertFalse(viewModel.loadFailed)
        XCTAssertEqual(fake.poemCalls, [42, 42])
    }

    func testLoadedPoemIsNotFetchedAgain() async {
        let fake = FakeContentRepository(poems: [poem])
        let viewModel = PoemViewModel(repository: fake)

        await viewModel.load(id: 42)
        await viewModel.load(id: 42)

        XCTAssertEqual(fake.poemCalls, [42])
    }
}
