// Minimum iOS 17.
//  Shared state of one reader: loaded poems by id, failures, and which page's title has scrolled under the bar
//  (the toolbar shows that poem's running head).

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

    @ObservationIgnored private let service = PoemsService(httpClient: URLSession.shared)

    /// Uses `cached` when the poem already arrived whole with a list or from the reader's likes.
    func load(_ id: Int, cached: Poem? = nil) async {
        guard poems[id] == nil, !loading.contains(id) else { return }
        if let cached {
            store(cached)
            return
        }
        loading.insert(id)
        defer { loading.remove(id) }
        do {
            let poem: Poem = try await service.fetch(.fetchPoem(id: id))
            store(poem)
        } catch {
            failed.insert(id)
        }
    }

    func retry(_ id: Int) async {
        failed.remove(id)
        await load(id)
    }

    private func store(_ poem: Poem) {
        parsed[poem.id] = ParsedPoem(poem.content)
        poems[poem.id] = poem
        failed.remove(poem.id)
    }
}
