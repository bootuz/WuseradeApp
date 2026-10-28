// Minimum iOS 17.
//  What the screens read from the back end: the newest poems, the themes and the poets, plus the poems of one
//  poet or theme and search. Lists keep what they last loaded, so a failed refresh never empties a screen.
//  Poems that arrive whole are remembered, so the reader opens them without another request.

import Foundation
import Observation

@MainActor
@Observable
final class Catalog {
    /// Home shows the first five; the regular-width УсэщӀэхэр column shows them all.
    private(set) var latest: [PoemSummary]?
    private(set) var themes: [Category]?
    /// Today's poem, chosen by `daysSource`; nil until it arrives or when it cannot be chosen offline.
    private(set) var daysPoem: Poem?
    private(set) var poets: [Author]?
    /// The first load found nothing and could not reach the server.
    private(set) var homeFailed = false
    private(set) var poetsFailed = false
    /// A refresh failed while older content stayed on screen.
    private(set) var refreshFailed = false

    @ObservationIgnored var daysSource: any DaysPoemSource = DailyRotation()
    @ObservationIgnored private var poems: [Int: Poem] = [:]
    @ObservationIgnored private let poemsService = PoemsService(httpClient: URLSession.shared)
    @ObservationIgnored private let authorsService = AuthorsService(httpClient: URLSession.shared)
    @ObservationIgnored private let themesService = CategoriesService(httpClient: URLSession.shared)

    // MARK: Home

    func loadHome() async {
        guard latest == nil || themes == nil else { return }
        await refreshHome()
    }

    func refreshHome() async {
        async let latestPoems: [Poem] = poemsService.fetch(.fetchLatestPoems)
        async let allThemes: [Category] = themesService.fetch(.categories)
        do {
            let (poems, themes) = try await (latestPoems, allThemes)
            remember(poems)
            latest = poems.map(PoemSummary.init)
            self.themes = themes.map { Category(id: $0.id, title: $0.title.kbd) }
            homeFailed = false
            refreshFailed = false
        } catch {
            if latest == nil { homeFailed = true } else { refreshFailed = true }
        }
        if let pick = await daysSource.poem(for: .now) {
            remember([pick])
            daysPoem = pick
        }
    }

    // MARK: Poets

    func loadPoets() async {
        guard poets == nil else { return }
        await refreshPoets()
    }

    func refreshPoets() async {
        do {
            let authors: [Author] = try await authorsService.fetch(.authorsV2)
            poets = authors.map { Author(id: $0.id, name: $0.name.kbd) }
            poetsFailed = false
        } catch {
            if poets == nil { poetsFailed = true }
        }
    }

    // MARK: Lists and search

    func poems(ofPoet id: Int) async throws -> [PoemSummary] {
        let poems: [Poem] = try await authorsService.fetch(.poemsOfAuthor(id: id))
        remember(poems)
        return poems.map(PoemSummary.init).sorted { KabardianAlphabet.precedes(sortKey($0), sortKey($1)) }
    }

    func poems(ofTheme id: Int) async throws -> [PoemSummary] {
        let poems: [Poem] = try await themesService.fetch(.poemsByCategory(id: id))
        remember(poems)
        return poems.map(PoemSummary.init)
    }

    /// The server matches titles and poet names, case-insensitively, so both palochka code points match.
    func search(_ query: String) async throws -> [PoemSummary] {
        let folded = query.kbd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else { return [] }
        let found: [Poem] = try await poemsService.fetch(.searchPoems(query: folded))
        remember(found)
        return found.map(PoemSummary.init)
    }

    // MARK: Whole poems

    func poem(_ id: Int) -> Poem? { poems[id] }

    func remember(_ poems: [Poem]) {
        for poem in poems where !poem.content.isEmpty { self.poems[poem.id] = poem }
    }

    private func sortKey(_ poem: PoemSummary) -> String {
        poem.isUntitled ? poem.firstLine : poem.title
    }
}
