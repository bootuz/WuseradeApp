//
//  SeachViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 18.02.2024.
//

import Foundation
import Observation

/// Searches the cached catalog as the user types.
@MainActor
@Observable
final class SearchViewModel {
    /// A pause in typing this long runs the search, so a burst of keystrokes costs one search
    /// (a search over ~5k entries takes ~14 ms).
    static let debounce: Duration = .milliseconds(150)

    var query = ""
    private(set) var results: [PoemSummary] = []

    /// Searches `entries` for the current `query` after `debounce`. Meant to be called from `.task(id:)`
    /// keyed on the query and catalog version: SwiftUI cancels the pending call when either changes,
    /// which is what debounces typing. A blank query clears the results at once.
    func search(in entries: [PoemSummary]) async {
        let query = query
        guard !CatalogSearch.normalize(query).isEmpty else {
            results = []
            return
        }
        do {
            try await Task.sleep(for: Self.debounce)
        } catch {
            return // Cancelled: a newer query or catalog took over.
        }
        // Off the main actor, so typing stays smooth while it runs.
        let found = await Task.detached(priority: .userInitiated) {
            CatalogSearch.search(query, in: entries)
        }.value
        guard !Task.isCancelled else { return }
        results = found
    }
}
