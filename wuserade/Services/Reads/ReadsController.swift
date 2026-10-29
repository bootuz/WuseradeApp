// Minimum iOS 17.
//  Writes the current account's reading history. Each poem is written once per account: the IDs already written
//  are remembered on the device, per uid, in `reads.known.<uid>`.

import Foundation
import Observation
import os

@MainActor
@Observable
final class ReadsController {
    /// The account reads are written to. Nil until the first (anonymous) sign-in succeeds; nothing is written then.
    private(set) var uid: String?

    @ObservationIgnored private let store: any ReadsStore
    @ObservationIgnored private let defaults: UserDefaults
    /// The poems of `uid` already written, or being written now.
    @ObservationIgnored private var known: Set<Int> = []

    init(store: any ReadsStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// Writes reads to `uid` from now on. Binding the account that is already bound changes nothing.
    func bind(uid: String?) {
        guard uid != self.uid else { return }
        self.uid = uid
        known = uid.map { Set(defaults.array(forKey: Self.key($0)) as? [Int] ?? []) } ?? []
    }

    /// Writes the read of `poemId` unless this account already has it. A failed write is logged and dropped, so
    /// the next read of the poem tries again.
    func markRead(_ poemId: Int) {
        guard let uid, known.insert(poemId).inserted else { return }
        Task {
            do {
                try await store.markRead(poemId: poemId, uid: uid)
                remember(poemId, uid: uid)
            } catch {
                Self.logger.error("Could not save the read of poem \(poemId): \(error.localizedDescription, privacy: .public)")
                if self.uid == uid { known.remove(poemId) }
            }
        }
    }

    /// Adds the poem to the IDs saved for `uid`, which may no longer be the bound account.
    private func remember(_ poemId: Int, uid: String) {
        let key = Self.key(uid)
        var saved = Set(defaults.array(forKey: key) as? [Int] ?? [])
        guard saved.insert(poemId).inserted else { return }
        defaults.set(saved.sorted(), forKey: key)
    }

    private static func key(_ uid: String) -> String {
        "reads.known.\(uid)"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "ReadsController"
    )
}
