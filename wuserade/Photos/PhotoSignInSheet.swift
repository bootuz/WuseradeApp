// Minimum iOS 17.
//  What a reader who is not signed in sees on tapping "send a photo": why sending needs an account, and the
//  Apple and Google buttons. `SendPhotoArea` closes it once the sign-in has worked.

import SwiftUI

struct PhotoSignInSheet: View {
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.four) {
                    Text(OwnerCopy.signInToSendPhoto)
                        .serif(.emptyTitle)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(OwnerCopy.whySendingNeedsAccount)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                    SignInButtons(isWorking: $isWorking)
                        .padding(.top, Space.two)
                }
                .padding(.horizontal, Space.four)
                .padding(.vertical, Space.six)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton()
                        .disabled(isWorking)
                }
            }
        }
        // A provider's sheet or sign-in is bounded by the system UI, so closing is held back while one runs.
        .interactiveDismissDisabled(isWorking)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.pageElevated)
        .modifier(FormSheetSizing())
    }
}
