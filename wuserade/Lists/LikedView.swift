// Minimum iOS 17.
//  Сигу ирихьахэр: liked poems, newest like first. A trailing swipe unlikes at once. Likes live on this device
//  until accounts move them to Firestore, and they open in the reader without a connection.

import FirebaseAnalytics
import SwiftData
import SwiftUI

struct LikedView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(\.modelContext) private var context
    @Query(sort: \PersistedPoem.persistedDate, order: .reverse) private var liked: [PersistedPoem]

    var body: some View {
        Group {
            if liked.isEmpty {
                ScrollView {
                    EmptyStateView(title: "Уигу ирихьа усэхэр мыбдеж къридзэнущ.", message: OwnerCopy.likedEmptyBody)
                }
            } else {
                PoemList(poems: liked.map(PoemSummary.init), onUnlike: unlike)
            }
        }
        .background(Palette.page)
        .navigationTitle("Сигу ирихьахэр")
        .onChange(of: liked.count, initial: true) {
            catalog.remember(liked.map(Poem.toPoem))
        }
        .analyticsScreen(name: "LikedPoemsView")
    }

    private func unlike(_ poem: PoemSummary) {
        guard let persisted = liked.first(where: { $0.poemID == poem.id }) else { return }
        context.delete(persisted)
        AnalyticsManager.shared.logEvent(name: "poem", params: ["unlike": persisted.title])
    }
}
