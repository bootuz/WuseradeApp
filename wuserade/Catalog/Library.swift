// Minimum iOS 17.
//  What the screens read: the newest poems, the themes and the poets from the cached Firestore catalog, the
//  poems of one poet or theme, search, whole poems, and the day's picks. Lists come from `CatalogStore`, so they
//  are there at once from the on-disk cache and never empty on a failed refresh. Whole poems are read one at a
//  time from `poems/{id}` and remembered, so the reader opens them again without another read. The day's picks
//  come from the server's `daily/{date}` document, kept in the App Group so Home shows them offline.

import Foundation
import Observation

@MainActor
@Observable
final class Library {
    let store: CatalogStore
    /// Today's picks; nil until they arrive, or when today's document can be neither loaded nor found cached.
    private(set) var daily: DailyPicks?

    /// Today's poem, from `daily`.
    var daysPoem: Poem? { daily?.poem.poem }

    @ObservationIgnored private let dailyStore: any DailyStore
    @ObservationIgnored private let dailyCache: DailyCache
    @ObservationIgnored private var poems: [Int: Poem] = [:]

    /// The regular-width УсэщӀэхэр column shows this many; Home shows the first five.
    static let latestCount = 9

    init(store: CatalogStore, dailyStore: any DailyStore = FirestoreDailyStore(), dailyCache: DailyCache = .shared) {
        self.store = store
        self.dailyStore = dailyStore
        self.dailyCache = dailyCache
    }

    // MARK: Lists

    var latest: [PoemSummary]? {
        store.catalog.map { Array($0.newestFirst().prefix(Self.latestCount)) }
    }

    var themes: [Category]? {
        store.meta.map { meta in meta.themes.map { Category(id: $0.id, title: $0.title.kbd) } }
    }

    var poets: [Author]? {
        store.meta.map { meta in meta.authors.map { Author(id: $0.id, name: $0.name.kbd) } }
    }

    /// Nothing has ever loaded, and the last try could not reach Firestore.
    var homeFailed: Bool { store.catalog == nil && store.lastError != nil && !store.isLoading }
    var poetsFailed: Bool { store.meta == nil && store.lastError != nil && !store.isLoading }
    /// A refresh failed while older content stayed on screen.
    var refreshFailed: Bool { store.catalog != nil && store.lastError != nil && !store.isLoading }

    /// A poet's poems in Kabardian alphabetical order; nil until the catalog has loaded.
    func poems(ofPoet id: Int) -> [PoemSummary]? {
        store.catalog?.poems(byAuthor: id).sorted { KabardianAlphabet.precedes(sortKey($0), sortKey($1)) }
    }

    /// A theme's poems, newest first; nil until the catalog has loaded.
    func poems(ofTheme id: Int) -> [PoemSummary]? {
        store.catalog?.poems(inTheme: id)
    }

    /// Titles and poet names, matched on the device, with every way of typing the palochka.
    func search(_ query: String) async throws -> [PoemSummary] {
        if store.catalog == nil { await store.refresh() }
        guard let catalog = store.catalog else { throw store.lastError ?? LibraryError.notLoaded }
        return CatalogSearch.search(query, in: catalog.entries)
    }

    // MARK: Poet photos

    /// A poet's approved photo, or nil when meta lists none, the poet is not in meta, or the stored string is
    /// not an absolute http(s) URL.
    func photoURL(ofPoet id: Int) -> URL? {
        guard let entry = store.meta?.authors.first(where: { $0.id == id }),
              let string = entry.photoURL,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// The id of every poet in meta, in meta's order. Loads meta first when nothing has loaded yet, and throws
    /// why it could not.
    func poetIDs() async throws -> [Int] {
        if store.meta == nil { await store.refresh() }
        guard let meta = store.meta else { throw store.lastError ?? LibraryError.notLoaded }
        return meta.authors.map(\.id)
    }

    // MARK: Loading

    func loadHome() async {
        if store.catalog == nil { await store.refresh() }
        await loadDaily()
    }

    func refreshHome() async {
        await store.refresh()
        await loadDaily(now: .now, alwaysFetch: true)
    }

    func loadPoets() async {
        if store.meta == nil { await store.refresh() }
    }

    func refreshPoets() async {
        await store.refresh()
    }

    /// Today's picks: the cached ones when they are today's, or else today's document, which is then cached.
    /// When it cannot be loaded or does not exist, Home leaves the daily sections out unless today's are cached.
    func loadDaily(now: Date = .now) async {
        await loadDaily(now: now, alwaysFetch: false)
    }

    private func loadDaily(now: Date, alwaysFetch: Bool) async {
        let today = DailyDate.string(for: now)
        let kept = [daily, dailyCache.load()].compactMap { $0 }.first { $0.date == today }
        if !alwaysFetch, let kept {
            show(kept)
            return
        }
        if let fetched = try? await dailyStore.fetch(date: today) {
            dailyCache.save(fetched)
            show(fetched)
        } else if let kept {
            show(kept)
        } else {
            daily = nil
        }
    }

    private func show(_ picks: DailyPicks) {
        remember([picks.poem.poem, picks.shortPoem.poem])
        if daily != picks { daily = picks }
    }

    // MARK: Whole poems

    func poem(_ id: Int) -> Poem? { poems[id] }

    /// A poem opened before, or else its catalog entry.
    func summary(_ id: Int) -> PoemSummary? {
        if let poem = poems[id] { return PoemSummary(poem) }
        return store.catalog?.entries.first { $0.id == id }
    }

    func fetchPoem(_ id: Int) async throws -> Poem {
        if let poem = poems[id] { return poem }
        let poem = try await store.repository.fetchPoem(id: id)
        remember([poem])
        return poem
    }

    func remember(_ poems: [Poem]) {
        for poem in poems where !poem.content.isEmpty { self.poems[poem.id] = poem }
    }

    private func sortKey(_ poem: PoemSummary) -> String {
        poem.isUntitled ? poem.firstLine : poem.title
    }
}

enum LibraryError: Error {
    /// The catalog has never loaded and a refresh gave no reason.
    case notLoaded
}
