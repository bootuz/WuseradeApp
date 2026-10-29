// Minimum iOS 17.
//  Shared state of one reader: loaded poems by id, failures, the page on screen, and which page's title has scrolled
//  under the bar (the toolbar shows that poem's running head).

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

    private func store(_ poem: Poem) {
        parsed[poem.id] = ParsedPoem(poem.content)
        poems[poem.id] = poem
        failed.remove(poem.id)
    }
}
