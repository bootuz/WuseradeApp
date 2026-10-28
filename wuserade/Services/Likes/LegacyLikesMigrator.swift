import Foundation
import os
import SwiftData

/// Uploads the likes this device kept in SwiftData (`PersistedPoem`) before likes lived in
/// Firestore. It runs once per device: the flag is set only after the upload succeeded, so a
/// failed or interrupted attempt is simply repeated. Repeating is harmless, because a like's
/// document ID is its poem ID.
struct LegacyLikesMigrator {
    private static let flagKey = "didMigrateLocalLikes"

    let container: ModelContainer
    let store: LikesStore
    let defaults: UserDefaults

    /// Uploads the legacy likes to `uid`'s account unless that already happened on this device.
    /// Never throws; on failure the flag stays unset so the next call tries again.
    func migrateIfNeeded(uid: String) async {
        guard !defaults.bool(forKey: Self.flagKey) else { return }
        do {
            let likes = try legacyLikes()
            if !likes.isEmpty {
                try await store.setLikes(likes, uid: uid)
            }
            defaults.set(true, forKey: Self.flagKey)
        } catch {
            Self.logger.error("Could not upload the on-device likes: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The persisted poems as likes dated by when they were liked. A poem stored twice keeps the earliest date.
    private func legacyLikes() throws -> [Like] {
        let poems = try ModelContext(container).fetch(FetchDescriptor<PersistedPoem>())
        let likes = poems.map { poem in
            Like(
                poemId: poem.poemID,
                likedAt: poem.persistedDate,
                title: poem.title,
                authorId: poem.author.authorID,
                authorName: poem.author.name,
                text: poem.text
            )
        }
        return LikesMerge.merge(existing: [], incoming: likes)
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "wuserade",
        category: "LegacyLikesMigrator"
    )
}
