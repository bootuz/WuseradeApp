import Foundation
import os

/// Likes waiting to be merged into an account, kept on the device so a failed step of the
/// "credential already in use" flow never loses them. `AccountManager.start()` merges whatever
/// is left here into the current account.
struct PendingLikesStore {
    private static let key = "pendingLikesMerge"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ likes: [Like]) {
        guard !likes.isEmpty else {
            clear()
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(likes), forKey: Self.key)
        } catch {
            Self.logger.error("Could not save pending likes: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The saved likes, or an empty list when there are none or they cannot be read.
    func load() -> [Like] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        do {
            return try JSONDecoder().decode([Like].self, from: data)
        } catch {
            Self.logger.error("Could not read pending likes: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "PendingLikesStore"
    )
}
