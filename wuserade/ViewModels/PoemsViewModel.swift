//
//  PoemsViewModel.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation
import Observation

/// Pages a list that is already fully in memory (the cached catalog): the list starts with `pageSize`
/// rows and grows by another page as the user scrolls near the end of what is shown.
@Observable
final class PoemsViewModel {
    static let pageSize = 20
    /// How close to the end of the visible rows (in rows) a row must be to bring in the next page.
    static let prefetchDistance = 10

    private(set) var visibleCount = PoemsViewModel.pageSize

    func visible(_ all: [PoemSummary]) -> ArraySlice<PoemSummary> {
        all.prefix(visibleCount)
    }

    /// Shows the next page when `current` is `prefetchDistance` or fewer rows from the end of the visible slice.
    func loadMoreIfNeeded(current: PoemSummary, in all: [PoemSummary]) {
        guard visibleCount < all.count else { return }
        guard visible(all).suffix(Self.prefetchDistance).contains(where: { $0.id == current.id }) else { return }
        visibleCount = min(visibleCount + Self.pageSize, all.count)
    }
}
