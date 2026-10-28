// Minimum iOS 17.
//  The heart: heart.fill in `like` when liked, heart in ink when not. The shape carries the state.
//  Liking swaps the symbol and bounces it once, with the selection haptic. Likes belong to the Firebase account;
//  until one exists (offline at first launch) the heart stays tappable and a one-line notice says liking waits.

import SwiftUI

struct LikeButton: View {
    let poem: Poem

    @Environment(LikesController.self) private var likes
    @Environment(AccountManager.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0
    @State private var showsNotice = false

    private var isLiked: Bool { likes.isLiked(poem.id) }

    /// No account yet, or an account operation is running (a like written during a sign-in merge could be lost).
    private var canLike: Bool { likes.uid != nil && !account.isBusy }

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
        .popover(isPresented: $showsNotice) {
            Text(OwnerCopy.likeNeedsAccount)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .padding(Space.three)
                .presentationCompactAdaptation(.popover)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    showsNotice = false
                }
        }
    }

    private func toggle() {
        guard canLike else {
            showsNotice = true
            AccessibilityNotification.Announcement(OwnerCopy.likeNeedsAccount).post()
            return
        }
        let isLiking = !isLiked
        if isLiking, !reduceMotion { bounce += 1 }
        // The change shows at once; the write can take as long as it takes to reconnect.
        Task { await likes.toggle(poem) }
        AnalyticsManager.shared.logEvent(name: "poem", params: [isLiking ? "like" : "unlike": poem.title])
    }
}
