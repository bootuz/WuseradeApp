#if DEBUG
import Foundation

/// A few poems, authors and themes for SwiftUI previews.
enum PreviewContent {
    static let authors = [
        AuthorEntry(id: 1, name: "Усакlуэм и цlэр", poemsCount: 2),
        AuthorEntry(id: 2, name: "Тхакlуэм и цlэр", poemsCount: 1),
    ]

    static let themes = [
        Category(id: 1, title: "Лъагъуныгъэ"),
        Category(id: 2, title: "Хэку"),
    ]

    static let catalog = Catalog(version: 1, entries: [
        entry(1, title: "Гъатхэ", authorId: 1, themeId: 1, daysAgo: 3),
        entry(2, title: "Бжьыхьэ", authorId: 1, themeId: 2, daysAgo: 2),
        entry(3, title: "Щlымахуэ", authorId: 2, themeId: 1, daysAgo: 1),
    ])

    static let meta = ContentMeta(
        catalogVersion: catalog.version,
        catalogChunks: 1,
        authors: authors,
        themes: themes,
        nextPoemId: 4
    )

    /// Today's picks, for any date.
    static func daily(date: String) -> DailyPicks {
        DailyPicks(
            date: date,
            poem: DailyPoem(
                id: Poem.example.id,
                title: Poem.example.title,
                authorId: Poem.example.author.id,
                authorName: Poem.example.author.name,
                text: Poem.example.content
            ),
            shortPoem: DailyPoem(id: 2, title: "", authorId: 1, authorName: authors[0].name, text: "Бжьыхьэ\nТхьэмахуэ"),
            poet: DailyPoet(
                id: authors[0].id,
                name: authors[0].name,
                poemsCount: authors[0].poemsCount,
                photoURL: nil,
                topPoems: [DailyPoemRef(id: 1, title: "Гъатхэ"), DailyPoemRef(id: 2, title: "Бжьыхьэ")]
            )
        )
    }

    private static func entry(_ id: Int, title: String, authorId: Int, themeId: Int, daysAgo: Double) -> PoemSummary {
        PoemSummary(
            id: id,
            title: title,
            authorId: authorId,
            authorName: authors.first { $0.id == authorId }?.name ?? "",
            themeId: themeId,
            createdAt: Date(timeIntervalSinceNow: -daysAgo * 86_400)
        )
    }
}

/// Serves `PreviewContent` from memory, so a preview never reaches Firestore.
struct PreviewContentRepository: ContentRepository {
    struct Offline: Error {}

    /// When true every read fails, as on a first launch without network.
    var isOffline = false

    func fetchMeta() async throws -> MetaDocument {
        if isOffline { throw Offline() }
        return MetaDocument(minimumAppVersion: nil, meta: .success(PreviewContent.meta))
    }

    func fetchCatalogChunk(index: Int) async throws -> CatalogChunk {
        if isOffline { throw Offline() }
        return CatalogChunk(version: PreviewContent.catalog.version, entries: PreviewContent.catalog.entries)
    }

    func fetchPoem(id: Int) async throws -> Poem {
        if isOffline { throw Offline() }
        return Poem.example
    }
}

/// Serves `PreviewContent.daily` for any date, so a preview never reaches Firestore. When offline it throws.
struct PreviewDailyStore: DailyStore {
    var isOffline = false

    func fetch(date: String) async throws -> DailyPicks? {
        if isOffline { throw PreviewContentRepository.Offline() }
        return PreviewContent.daily(date: date)
    }
}

extension Library {
    /// A library for previews over `CatalogStore.preview(loaded:)`, with today's picks from `PreviewDailyStore`
    /// when `loaded`. It keeps no daily cache.
    static func preview(loaded: Bool = true) -> Library {
        Library(
            store: .preview(loaded: loaded),
            dailyStore: PreviewDailyStore(isOffline: !loaded),
            dailyCache: DailyCache(directory: nil)
        )
    }
}

extension CatalogStore {
    /// A store for previews, backed by its own temporary cache. When `loaded`, it starts with
    /// `PreviewContent`; otherwise it starts empty and every refresh fails (the offline first-launch state).
    static func preview(loaded: Bool = true) -> CatalogStore {
        let cache = CatalogCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewCatalog-\(UUID().uuidString)", isDirectory: true))
        if loaded {
            try? cache.save(CachedContent(meta: PreviewContent.meta, catalog: PreviewContent.catalog))
        }
        return CatalogStore(repository: PreviewContentRepository(isOffline: !loaded), cache: cache)
    }
}

/// Keeps likes in memory for previews, so a preview never reaches Firestore. Writes are ignored.
struct PreviewLikesStore: LikesStore {
    var likes: [Like] = []

    func fetchLikes(uid: String) async throws -> [Like] { likes }

    func observeLikes(uid: String) -> AsyncThrowingStream<[Like], Error> {
        AsyncThrowingStream { $0.yield(likes) }
    }

    func setLike(_ like: Like, uid: String) async throws {}
    func setLikes(_ likes: [Like], uid: String) async throws {}
    func removeLike(poemId: Int, uid: String) async throws {}
    func ensureUserDocument(uid: String) async throws {}
    func deleteAllData(uid: String) async throws {}
}

extension LikesController {
    /// A controller for previews, signed in as a made-up account whose likes are `likes`.
    static func preview(likes: [Like] = []) -> LikesController {
        let controller = LikesController(store: PreviewLikesStore(likes: likes))
        controller.bind(uid: "preview")
        return controller
    }
}

/// An `AuthBackend` for previews that never reaches Firebase. `currentUser` stays signed in; every change fails.
struct PreviewAuthBackend: AuthBackend {
    struct Unavailable: Error {}

    var currentUser: AuthUserInfo?

    func signInAnonymously() async throws -> AuthUserInfo { throw Unavailable() }
    func link(_ c: ProviderCredential) async throws -> AuthUserInfo { throw Unavailable() }
    func signIn(with c: ProviderCredential) async throws -> AuthUserInfo { throw Unavailable() }
    func reauthenticate(with c: ProviderCredential) async throws { throw Unavailable() }
    func revokeAppleToken(authorizationCode: String) async throws { throw Unavailable() }
    func deleteCurrentUser(expectedUID: String) async throws { throw Unavailable() }
    func signOut() throws { throw Unavailable() }
}

extension AccountManager {
    /// An account manager for previews. It starts out signed out; call `start()` for `user` to become the account.
    /// It never calls Firebase.
    static func preview(user: AuthUserInfo? = nil) -> AccountManager {
        AccountManager(
            auth: PreviewAuthBackend(currentUser: user),
            likes: PreviewLikesStore(),
            pending: PendingLikesStore(),
            deleteWaitingPhotos: { _ in },
            setAnalyticsUserID: { _ in }
        )
    }
}
#endif
