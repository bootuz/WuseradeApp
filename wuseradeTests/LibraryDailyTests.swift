import Foundation
import Testing
@testable import Wuserade

@MainActor
final class LibraryDailyTests {
    /// Swift Testing creates a fresh suite instance per test, so every test gets its own empty directories.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibraryDailyTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    /// 2026-10-29 at noon UTC, the same calendar day in every time zone from UTC-11 to UTC+11.
    private let now = Date(timeIntervalSince1970: 1_793_275_200)
    private var today: String { DailyDate.string(for: now) }

    private func picks(date: String, poemId: Int = 10) -> DailyPicks {
        DailyPicks(
            date: date,
            poem: DailyPoem(id: poemId, title: "Day", authorId: 3, authorName: "Author 3", text: "One\nTwo"),
            shortPoem: DailyPoem(id: poemId + 1, title: "", authorId: 4, authorName: "Author 4", text: "Short"),
            poet: DailyPoet(id: 5, name: "Author 5", poemsCount: 9, photoURL: nil, topPoems: [DailyPoemRef(id: 6, title: "Top")])
        )
    }

    private var cache: DailyCache { DailyCache(directory: directory.appendingPathComponent("daily", isDirectory: true)) }

    private func makeLibrary(_ dailyStore: FakeDailyStore) -> Library {
        Library(
            store: CatalogStore(repository: FakeContentRepository(), cache: CatalogCache(directory: directory.appendingPathComponent("catalog", isDirectory: true))),
            dailyStore: dailyStore,
            dailyCache: cache
        )
    }

    // MARK: Tests

    @Test func `todaysCacheIsUsedWithoutFetching`() async {
        cache.save(picks(date: today))
        let dailyStore = FakeDailyStore()
        let library = makeLibrary(dailyStore)

        await library.loadDaily(now: now)

        #expect(dailyStore.fetches.isEmpty)
        #expect(library.daily == picks(date: today))
        #expect(library.daysPoem?.id == 10)
    }

    @Test func `fetchedDailyIsCachedAndPoemsRemembered`() async {
        let dailyStore = FakeDailyStore()
        dailyStore.documents = [today: picks(date: today)]
        let library = makeLibrary(dailyStore)

        await library.loadDaily(now: now)

        #expect(dailyStore.fetches == [today])
        #expect(library.daily == picks(date: today))
        #expect(library.daysPoem == picks(date: today).poem.poem)
        #expect(cache.load() == picks(date: today))
        #expect(library.poem(10) == picks(date: today).poem.poem)
        #expect(library.poem(11) == picks(date: today).shortPoem.poem)
    }

    @Test func `offlineWithoutCacheLeavesDailyOut`() async {
        let dailyStore = FakeDailyStore()
        dailyStore.error = FakeDailyStore.Offline()
        let library = makeLibrary(dailyStore)

        await library.loadDaily(now: now)

        #expect(dailyStore.fetches == [today])
        #expect(library.daily == nil)
        #expect(library.daysPoem == nil)
    }

    @Test func `missingDocumentLeavesDailyOut`() async {
        let dailyStore = FakeDailyStore()
        let library = makeLibrary(dailyStore)

        await library.loadDaily(now: now)

        #expect(dailyStore.fetches == [today])
        #expect(library.daily == nil)
        #expect(cache.load() == nil)
    }

    @Test func `yesterdaysCacheIsNotToday`() async {
        cache.save(picks(date: "2026-10-28"))
        let dailyStore = FakeDailyStore()
        dailyStore.error = FakeDailyStore.Offline()
        let library = makeLibrary(dailyStore)

        await library.loadDaily(now: now)

        #expect(dailyStore.fetches == ["2026-10-29"])
        #expect(library.daily == nil)
    }

    @Test func `refreshFetchesEvenWithTodaysCache`() async {
        let realToday = DailyDate.string(for: .now)
        cache.save(picks(date: realToday))
        let dailyStore = FakeDailyStore()
        dailyStore.documents = [realToday: picks(date: realToday, poemId: 20)]
        let library = makeLibrary(dailyStore)

        await library.refreshHome()

        #expect(dailyStore.fetches == [realToday])
        #expect(library.daysPoem?.id == 20)
        #expect(cache.load()?.poem.id == 20)
    }

    @Test func `failedRefreshKeepsTodaysCache`() async {
        let realToday = DailyDate.string(for: .now)
        cache.save(picks(date: realToday))
        let dailyStore = FakeDailyStore()
        dailyStore.error = FakeDailyStore.Offline()
        let library = makeLibrary(dailyStore)

        await library.refreshHome()

        #expect(dailyStore.fetches == [realToday])
        #expect(library.daily == picks(date: realToday))
    }

    @Test func `cacheWithoutDirectoryStoresNothing`() {
        let cache = DailyCache(directory: nil)
        cache.save(picks(date: today))
        #expect(cache.load() == nil)
    }
}
