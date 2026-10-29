// Minimum iOS 17.
//  Writes the current account's reading history. Each poem is written once per account: the IDs already written
//  are remembered on the device, per uid, by `KnownReadsStore`. Nothing is written while `isPaused` says so.

import Foundation
import Observation
import os

@MainActor
@Observable
final class ReadsController {
    /// The account reads are written to. Nil until the first (anonymous) sign-in succeeds; nothing is written then.
    private(set) var uid: String?

    @ObservationIgnored private let store: any ReadsStore
    @ObservationIgnored private let knownReads: KnownReadsStore
    /// True while an account operation runs: a read written then could land on an account being deleted or merged.
    @ObservationIgnored private let isPaused: @MainActor () -> Bool
    /// The poems of `uid` already written, or being written now.
    @ObservationIgnored private var known: Set<Int> = []

    init(store: any ReadsStore, defaults: UserDefaults = .standard, isPaused: @escaping @MainActor () -> Bool = { false }) {
        self.store = store
        knownReads = KnownReadsStore(defaults: defaults)
        self.isPaused = isPaused
    }

    /// Writes reads to `uid` from now on. Binding the account that is already bound changes nothing.
    func bind(uid: String?) {
        guard uid != self.uid else { return }
        self.uid = uid
        known = uid.map { knownReads.load(uid: $0) } ?? []
    }

    /// Writes the read of `poemId` unless this account already has it. A failed write, or a read while paused, is
    /// dropped, so the next read of the poem tries again.
    func markRead(_ poemId: Int) {
        guard let uid, !isPaused(), known.insert(poemId).inserted else { return }
        Task {
            do {
                try await store.markRead(poemId: poemId, uid: uid)
                knownReads.add(poemId, uid: uid)
            } catch {
                Self.logger.error("Could not save the read of poem \(poemId): \(error.localizedDescription, privacy: .public)")
                if self.uid == uid { known.remove(poemId) }
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "ReadsController"
    )
}
