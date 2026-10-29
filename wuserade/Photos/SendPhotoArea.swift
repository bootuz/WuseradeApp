// Minimum iOS 17.
//  Under a poet's count line: the button that starts sending a photo, or the line saying one is waiting for review.
//  Which one shows, if any, is `SendAreaState`. A signed-in reader's waiting record is checked on the way in.
//  The button leads through the sign-in sheet (for a reader who is not signed in), the photo picker and the send
//  sheet. Every presentation hangs on the area's own stack, which is there in every state, so none of them is
//  torn down when the sign-in or the send turns the button into the waiting line.

import PhotosUI
import SwiftUI

struct SendPhotoArea: View {
    let poet: Author
    let hasPhoto: Bool

    @Environment(PhotoSubmissions.self) private var photos
    @Environment(AccountManager.self) private var account

    @State private var isSignInPresented = false
    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?
    /// The photo to send, once it is loaded and prepared. Setting it presents the send sheet.
    @State private var prepared: PreparedPhoto?
    /// True from the pick until the photo is ready or has failed, so the button cannot open the picker again.
    @State private var isPreparing = false
    @State private var isShowingLoadFailure = false

    /// A photo is being prepared, or one for this poet is still being sent. The send sheet can be closed while it
    /// sends, and this keeps the reader from starting a second send for the poet until the first one ends.
    private var isBusy: Bool { isPreparing || photos.isSending(poetID: poet.id) }

    private var state: SendAreaState {
        SendAreaState.resolve(
            hasPhoto: hasPhoto,
            isSignedIn: isSignedIn,
            waiting: photos.status(poetID: poet.id)
        )
    }

    /// What the check depends on: it starts again when the account, the poet or whether the poet has a photo changes.
    private struct CheckKey: Equatable {
        let uid: String?
        let poetID: Int
        let hasPhoto: Bool
    }

    var body: some View {
        // A VStack, not a Group: the check below is a task of this view, and it has to start while the area is
        // empty, which is where a signed-in reader begins. A Group with nothing in it has no view to hold the task.
        VStack(spacing: 0) {
            switch state {
            case .button:
                Button(action: startSending) {
                    // The label stays in place under the spinner, so the button does not change size.
                    Text(OwnerCopy.sendPhoto)
                        .opacity(isBusy ? 0 : 1)
                        .overlay {
                            if isBusy { ProgressView().tint(Palette.accent) }
                        }
                }
                .disabled(isBusy)
                .buttonStyle(.secondaryCapsule)
                .multilineTextAlignment(.center)
                .padding(.top, Space.four)
            case .waiting:
                Text(OwnerCopy.photoWaiting)
                    .serif(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.four)
            case .hidden:
                EmptyView()
            }
        }
        .task(id: CheckKey(uid: photos.uid, poetID: poet.id, hasPhoto: hasPhoto)) {
            if !hasPhoto { await photos.check(poetID: poet.id) }
        }
        .sheet(isPresented: $isSignInPresented, onDismiss: openPickerIfSignedIn) {
            PhotoSignInSheet()
        }
        .onChange(of: account.state) { _, state in
            if isSignInPresented, PhotoSubmissions.uid(for: state) != nil { isSignInPresented = false }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            isPreparing = true
            Task { await prepare(item) }
        }
        .sheet(item: $prepared) { photo in
            PhotoSendSheet(poet: poet, photo: photo)
        }
        .alert(AccountAlert.title, isPresented: $isShowingLoadFailure) {
            Button(AccountAlert.ok, role: .cancel) {}
        } message: {
            Text(OwnerCopy.photoSendFailed)
        }
    }

    // MARK: Flow

    private var isSignedIn: Bool { PhotoSubmissions.uid(for: account.state) != nil }

    private func startSending() {
        if isSignedIn {
            isPickerPresented = true
        } else {
            isSignInPresented = true
        }
    }

    /// Runs when the sign-in sheet has gone, not when the sign-in finishes: a presentation that starts while
    /// another is still being dismissed is dropped.
    private func openPickerIfSignedIn() {
        if isSignedIn { isPickerPresented = true }
    }

    /// Loads the picked photo and prepares it off the main actor, then presents the send sheet. Whatever goes
    /// wrong, the reader hears about it, and the picker is ready for the next pick.
    private func prepare(_ item: PhotosPickerItem) async {
        defer {
            pickedItem = nil
            isPreparing = false
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                isShowingLoadFailure = true
                return
            }
            prepared = try await Task.detached { try PhotoPreparation.prepare(data) }.value
        } catch {
            isShowingLoadFailure = true
        }
    }
}
