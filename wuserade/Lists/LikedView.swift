// Minimum iOS 17.
//  Сигу ирихьахэр: liked poems, newest like first. A trailing swipe unlikes at once. Likes belong to the
//  account and sync through Firestore; each keeps the poem's text, so it opens in the reader without a connection.

import FirebaseAnalytics
import SwiftUI

struct LikedView: View {
    @Environment(Library.self) private var library
    @Environment(LikesController.self) private var likes

    var body: some View {
        Group {
            if likes.likes.isEmpty {
                ScrollView {
                    EmptyStateView(title: "Уигу ирихьа усэхэр мыбдеж къридзэнущ.", message: OwnerCopy.likedEmptyBody)
                }
            } else {
                PoemList(poems: likes.likes.map(PoemSummary.init), onUnlike: unlike)
            }
        }
        .background(Palette.page)
        .navigationTitle("Сигу ирихьахэр")
        .onChange(of: likes.likes, initial: true) {
            library.remember(likes.likes.map(\.poem))
        }
        .analyticsScreen(name: "LikedPoemsView")
    }

    private func unlike(_ poem: PoemSummary) {
        guard let like = likes.likes.first(where: { $0.poemId == poem.id }) else { return }
        Task { await likes.toggle(like.poem) }
        AnalyticsManager.shared.logEvent(name: "poem", params: ["unlike": like.title])
    }
}
