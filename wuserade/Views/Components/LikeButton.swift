//
//  LikeButton.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI
import Pow

struct LikeButton: View {
    @Environment(LikesController.self) private var likes
    @Environment(AccountManager.self) private var account
    @State private var shouldAnimate: Bool = false

    var poem: Poem
    let onAnalyticsEvent: ((String, [String: String]) -> Void)?

    init(for poem: Poem, onAnalyticsEvent: ((String, [String : String]) -> Void)?) {
        self.poem = poem
        self.onAnalyticsEvent = onAnalyticsEvent
    }

    private var isLiked: Bool {
        likes.isLiked(poem.id)
    }

    /// Off until an account exists, and while an account operation runs (a like written during a
    /// sign-in merge could be lost).
    private var isDisabled: Bool {
        likes.uid == nil || account.isBusy
    }

    var body: some View {
        Button {
            shouldAnimate = true
            let isLiking = !isLiked
            // The change shows at once; the write can take as long as it takes to reconnect.
            Task { await likes.toggle(poem) }
            onAnalyticsEvent?("poem", [isLiking ? "like" : "unlike": poem.title])
        } label: {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadToggleImage()
            } else {
                toggleImage()
            }
        }
        .buttonStyle(LikeButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.default, value: isLiked)
    }

    @ViewBuilder
    private func toggleImage() -> some View {
        if isLiked {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
                .transition(shouldAnimate ? .movingParts.pop(.red) : .identity)
        } else {
            Image(systemName: "heart")
                .foregroundStyle(.primary)
                .transition(.identity)
        }
    }

    @ViewBuilder
    private func iPadToggleImage() -> some View {
        if isLiked {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
        } else {
            Image(systemName: "heart")
                .foregroundStyle(.primary)
        }
    }
}

struct LikeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sensoryFeedback(.impact(weight: .heavy, intensity: 5.0), trigger: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    LikeButton(for: Poem.example, onAnalyticsEvent: AnalyticsManager.shared.logEvent)
        .environment(LikesController.preview())
        .environment(AccountManager.preview())
        .font(.system(size: 60))
}
#endif
