// Minimum iOS 17.
//  The heart: heart.fill in `like` when liked, heart in ink when not. The shape carries the state.
//  Liking swaps the symbol and bounces it once, with the selection haptic.
//  Likes stay on this device in SwiftData until the accounts work moves them to Firestore.

import SwiftData
import SwiftUI

struct LikeButton: View {
    let poem: Poem

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var liked: [PersistedPoem]
    @State private var bounce = 0

    init(poem: Poem) {
        self.poem = poem
        let id = poem.id
        _liked = Query(filter: #Predicate<PersistedPoem> { $0.poemID == id })
    }

    private var isLiked: Bool { !liked.isEmpty }

    var body: some View {
        Button {
            toggle()
        } label: {
            Label(isLiked ? OwnerCopy.unlike : OwnerCopy.like, systemImage: isLiked ? "heart.fill" : "heart")
                .foregroundStyle(isLiked ? Palette.like : Palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounce)
        }
        .sensoryFeedback(.selection, trigger: isLiked)
        .accessibilityAddTraits(isLiked ? .isSelected : [])
    }

    private func toggle() {
        if let existing = liked.first {
            context.delete(existing)
            AnalyticsManager.shared.logEvent(name: "poem", params: ["unlike": poem.title])
        } else {
            context.insert(PersistedPoem.toPersistedPoem(from: poem))
            if !reduceMotion { bounce += 1 }
            AnalyticsManager.shared.logEvent(name: "poem", params: ["like": poem.title])
        }
    }
}
