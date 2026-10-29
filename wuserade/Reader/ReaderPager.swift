// Minimum iOS 17.
//  Shared state of one reader: loaded poems by id, failures, the page on screen, which page's title has scrolled
//  under the bar (the toolbar shows that poem's running head), and the suggestions that arrived after each poem.

import Foundation
import Observation

@MainActor
@Observable
final class ReaderPager {
    private(set) var poems: [Int: Poem] = [:]
    /// Parsed once on load; a long poem runs to about 3,000 lines.
    private(set) var parsed: [Int: ParsedPoem] = [:]
    private(set) var failed: Set<Int> = []
    private(set) var loading: Set<Int> = []
    var titleUnderBar: [Int: Bool] = [:]
    /// The poem whose page is on screen. Pages beside it may be laid out, but only this one is being read.
    var currentID: Int?
    /// The server's suggestions after each poem, for `suggestionsUid`. They live here rather than in a page, so
    /// a page the lazy stack tears down and rebuilds shows them again without another call.
    private(set) var suggestions: [Int: KeepReading] = [:]
    /// The account the suggestions were asked for: the server leaves out that account's reads.
    private(set) var suggestionsUid: String?
    @ObservationIgnored private var suggesting: Set<Int> = []

    /// Uses the library's copy when the poem was opened before or came with the reader's likes; otherwise one
    /// read of `poems/{id}`.
    func load(_ id: Int, from library: Library) async {
        guard poems[id] == nil, !loading.contains(id) else { return }
        if let cached = library.poem(id) {
            store(cached)
            return
        }
        loading.insert(id)
        defer { loading.remove(id) }
        do {
            store(try await library.fetchPoem(id))
        } catch {
            failed.insert(id)
        }
    }

    func retry(_ id: Int, from library: Library) async {
        failed.remove(id)
        await load(id, from: library)
    }

    /// Forgets every suggestion when the account changes, since they left out the previous account's reads.
    func bindSuggestions(uid: String?) {
        guard uid != suggestionsUid else { return }
        suggestionsUid = uid
        suggestions = [:]
        suggesting = []
    }

    /// Asks once per poem and account, and keeps what arrives. A failure keeps nothing, so the poem asks again the
    /// next time its page wants suggestions. An answer for an account no longer bound is dropped.
    func loadSuggestions(_ id: Int, from service: any KeepReadingService) async {
        guard suggestions[id] == nil, !suggesting.contains(id) else { return }
        let uid = suggestionsUid
        suggesting.insert(id)
        let result = await KeepReadingState.load(id, from: service)
        guard uid == suggestionsUid else { return }
        suggesting.remove(id)
        if case .success(let found) = result {
            suggestions[id] = found
        }
    }

    private func store(_ poem: Poem) {
        parsed[poem.id] = ParsedPoem(poem.content)
        poems[poem.id] = poem
        failed.remove(poem.id)
    }
}
