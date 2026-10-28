import XCTest
@testable import Wuserade

final class PoemsViewModelTests: XCTestCase {
    /// `count` entries with ids 1...count, already newest first.
    private func entries(_ count: Int) -> [PoemSummary] {
        (1...count).map { id in
            PoemSummary(
                id: id,
                title: "Poem \(id)",
                authorId: 1,
                authorName: "Author",
                themeId: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(id) * 86_400)
            )
        }
    }

    func testStartsWithTwenty() {
        let all = entries(45)
        let viewModel = PoemsViewModel()

        XCTAssertEqual(PoemsViewModel.pageSize, 20)
        XCTAssertEqual(viewModel.visibleCount, 20)
        XCTAssertEqual(viewModel.visible(all).map(\.id), Array(1...20))
    }

    func testLoadsNextPageNearEnd() {
        let all = entries(45)
        let viewModel = PoemsViewModel()

        // Index 10 is the 10th row from the end of the 20 visible rows.
        viewModel.loadMoreIfNeeded(current: all[10], in: all)
        XCTAssertEqual(viewModel.visibleCount, 40)
        XCTAssertEqual(viewModel.visible(all).count, 40)

        viewModel.loadMoreIfNeeded(current: all[39], in: all)
        XCTAssertEqual(viewModel.visibleCount, 45)
        XCTAssertEqual(viewModel.visible(all).map(\.id), Array(1...45))

        // Everything is visible: no further growth.
        viewModel.loadMoreIfNeeded(current: all[44], in: all)
        XCTAssertEqual(viewModel.visibleCount, 45)
    }

    func testRowFartherThanTenFromEndDoesNotLoad() {
        let all = entries(45)
        let viewModel = PoemsViewModel()

        // Index 9 is 11 rows from the end of the visible slice.
        viewModel.loadMoreIfNeeded(current: all[9], in: all)
        XCTAssertEqual(viewModel.visibleCount, 20)

        // A row that is not visible at all never triggers a page.
        viewModel.loadMoreIfNeeded(current: all[30], in: all)
        XCTAssertEqual(viewModel.visibleCount, 20)
    }

    func testShortListShowsEverythingWithoutPaging() {
        let all = entries(5)
        let viewModel = PoemsViewModel()

        XCTAssertEqual(viewModel.visible(all).count, 5)
        viewModel.loadMoreIfNeeded(current: all[4], in: all)
        XCTAssertEqual(viewModel.visible(all).count, 5)
    }
}
