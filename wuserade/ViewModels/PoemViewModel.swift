//
//  PoemViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import Foundation
import Observation
import os

/// Loads a single poem from the content repository.
@MainActor
@Observable
final class PoemViewModel {
    private(set) var poem: Poem?
    /// True after a load failed; cleared when the next `load(id:)` starts.
    private(set) var loadFailed = false

    @ObservationIgnored private let repository: ContentRepository

    /// Pass `preloaded` when the poem is already in hand; it is shown at once and `load(id:)` leaves the repository alone.
    init(repository: ContentRepository, preloaded: Poem? = nil) {
        self.repository = repository
        self.poem = preloaded
    }

    /// Reads poem `id` unless a poem is already showing. Safe to call again after a failure (retry).
    func load(id: Int) async {
        guard poem == nil else { return }
        loadFailed = false
        do {
            poem = try await repository.fetchPoem(id: id)
        } catch {
            // A cancelled load (the user left the screen) is not a failure; the next appearance loads again.
            guard !Task.isCancelled else { return }
            Self.logger.error("Could not load poem \(id): \(error.localizedDescription)")
            loadFailed = true
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "PoemViewModel"
    )
}
