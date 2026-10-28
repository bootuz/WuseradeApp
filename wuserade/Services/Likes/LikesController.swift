import Foundation
import Observation
import os

/// The likes of the current account, kept in step with Firestore. `bind(uid:)` points it at an
/// account; the Liked tab and every like button read it.
///
/// Until an account exists (`uid == nil`) there are no likes and `toggle` does nothing.
@MainActor
@Observable
final class LikesController {
    /// The current account's likes, newest first. Empty while `uid` is nil.
    private(set) var likes: [Like] = []
    /// The account the likes belong to. Nil until the first (anonymous) sign-in succeeds.
    private(set) var uid: String?

    @ObservationIgnored private let store: LikesStore
    @ObservationIgnored private var observation: Task<Void, Never>?
    /// Every toggle takes the next number; `latestToggle` remembers the newest one per poem.
    @ObservationIgnored private var toggleCount = 0
    @ObservationIgnored private var latestToggle: [Int: Int] = [:]

    init(store: LikesStore) {
        self.store = store
    }

    deinit {
        observation?.cancel()
    }

    /// Shows the likes of `uid`. The previous account's listener is stopped and its likes are
    /// cleared before the new one is observed, so they can never appear under the new account.
    /// Binding the account that is already bound changes nothing.
    func bind(uid: String?) {
        guard uid != self.uid else { return }
        observation?.cancel()
        observation = nil
        likes = []
        self.uid = uid
        guard let uid else { return }

        let snapshots = store.observeLikes(uid: uid)
        observation = Task { [weak self] in
            do {
                for try await snapshot in snapshots {
                    // A snapshot of an account that was bound away from can still be on its way.
                    guard let self, !Task.isCancelled else { return }
                    self.likes = snapshot
                }
            } catch {
                Self.logger.error("Likes listener stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func isLiked(_ poemId: Int) -> Bool {
        likes.contains { $0.poemId == poemId }
    }

    /// Likes the poem, or unlikes it when it is liked. The change shows at once; the write then
    /// runs, and offline it only finishes once the device reconnects. If it fails the change is
    /// undone, unless the poem was toggled again meanwhile (or the account switched), in which
    /// case the newer state stands. Does nothing without an account.
    func toggle(_ poem: Poem) async {
        guard let uid else { return }

        let existing = likes.first { $0.poemId == poem.id }
        let added = existing == nil ? Like(poem: poem) : nil
        toggleCount += 1
        let token = toggleCount
        latestToggle[poem.id] = token

        replaceLike(of: poem.id, with: added)
        do {
            if let added {
                try await store.setLike(added, uid: uid)
            } else {
                try await store.removeLike(poemId: poem.id, uid: uid)
            }
        } catch {
            Self.logger.error("Could not save the like of poem \(poem.id): \(error.localizedDescription, privacy: .public)")
            guard latestToggle[poem.id] == token, self.uid == uid else { return }
            replaceLike(of: poem.id, with: existing)
        }
    }

    /// Sets the like of one poem in the list (`nil` removes it), keeping the newest-first order.
    private func replaceLike(of poemId: Int, with like: Like?) {
        likes.removeAll { $0.poemId == poemId }
        guard let like else { return }
        likes.append(like)
        likes.sort { ($0.likedAt, $0.poemId) > ($1.likedAt, $1.poemId) }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "LikesController"
    )
}
