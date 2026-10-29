// Minimum iOS 17.
//  The last step of sending a photo: the prepared photo in the poet's circle, the poet's name, the line about
//  rights, and Send. A failure shows under the text; only a blocked account has no way to try again.

import SwiftUI

struct PhotoSendSheet: View {
    let poet: Author
    let photo: PreparedPhoto

    struct FailureMessage: Equatable {
        let text: String
        let canRetry: Bool
    }

    /// Only a blocked account is told to stop; every other failure (the network, the server, a sign-in that ended
    /// meanwhile) is worth another try.
    static func failureMessage(for error: Error) -> FailureMessage {
        switch error as? PhotoSubmissionError {
        case .banned?: FailureMessage(text: OwnerCopy.photoSendBanned, canRetry: false)
        default: FailureMessage(text: OwnerCopy.photoSendFailed, canRetry: true)
        }
    }

    @Environment(PhotoSubmissions.self) private var photos
    @Environment(\.dismiss) private var dismiss
    /// Set at once on the tap, not when `PhotoSubmissions` starts the send, so a second tap right behind the
    /// first finds it already running.
    @State private var isSending = false
    @State private var failure: FailureMessage?
    /// False once the sheet has gone. Close stays enabled while sending (a dead network must not trap the
    /// reader), and closing cancels nothing, so the send can finish after the sheet is gone.
    @State private var isOnScreen = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.four) {
                    PoetPortrait(initials: PoetInitials.of(poet.name), image: photo.image)
                    Text(poet.name)
                        .serif(.emptyTitle)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(OwnerCopy.photoRights)
                        .serif(.prose)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                    if let failure {
                        Text(failure.text)
                            .font(.footnote)
                            .foregroundStyle(Palette.destructive)
                            .multilineTextAlignment(.center)
                    }
                    sendButton
                        .padding(.top, Space.two)
                }
                .padding(.horizontal, Space.four)
                .padding(.vertical, Space.six)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton()
                }
            }
        }
        .onDisappear { isOnScreen = false }
        // Only the swipe is held back, against an accidental one; Close always works.
        .interactiveDismissDisabled(isSending)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.pageElevated)
        .modifier(FormSheetSizing())
    }

    private var canSend: Bool { failure?.canRetry ?? true }

    private var sendButton: some View {
        Button(action: send) {
            // The label stays in place under the spinner, so the button does not change size while sending.
            Text(OwnerCopy.send)
                .opacity(isSending ? 0 : 1)
                .overlay {
                    if isSending { ProgressView().tint(Palette.onAccent) }
                }
        }
        .buttonStyle(.primaryCapsule(fullWidth: true))
        .disabled(isSending || !canSend)
        .opacity(canSend ? 1 : 0.4)
    }

    private func send() {
        guard !isSending else { return }
        isSending = true
        failure = nil
        Task {
            defer { isSending = false }
            do {
                try await photos.send(photo.jpeg, for: poet.id)
                // Closed meanwhile: this sheet's dismiss would now close whichever sheet the area shows next.
                // The announcement still says what happened, wherever the reader is.
                if isOnScreen { dismiss() }
                AccessibilityNotification.Announcement(OwnerCopy.photoWaiting).post()
            } catch {
                let message = Self.failureMessage(for: error)
                failure = message
                AccessibilityNotification.Announcement(message.text).post()
            }
        }
    }
}
