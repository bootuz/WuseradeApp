// Minimum iOS 17.
//  Аккаунт, the first sections of Settings. While the account is anonymous (or there is none yet): one line on
//  why to sign in, then `SignInButtons`. Once signed in: the method and the email, Sign out with its
//  confirmation, and a separate section for deleting the account.
//  The strings are the owner's placeholders from the Firebase work; the ones in brackets are still open.

import SwiftUI

struct AccountSection: View {
    @Environment(AccountManager.self) private var account
    /// True from the tap on a button until its flow ends, the Apple or Google sheet included.
    /// `account.isBusy` only starts once the sheet is done, and Google's flow has no guard against a second tap.
    @State private var isWorking = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var alertMessage: String?

    /// A flow can last until the device reconnects (writes wait for the server), so only these sections
    /// are locked while it runs, never the rest of Settings. The sign-in buttons run their flow through `isWorking` too.
    private var isDisabled: Bool { isWorking || account.isBusy }

    var body: some View {
        Section {
            switch account.state {
            case .signedOut, .anonymous:
                VStack(alignment: .leading, spacing: Space.three) {
                    Text(Self.signInExplanation)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    SignInButtons(isWorking: $isWorking)
                }
                .padding(.vertical, Space.two)
            case let .signedIn(_, provider, email):
                statusRow(provider: provider, email: email)
                Button(Self.signOutTitle) { isConfirmingSignOut = true }
                    .disabled(isDisabled)
                    .confirmationDialog(OwnerCopy.signOutQuestion, isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                        Button(Self.signOutTitle, role: .destructive) {
                            run { try await account.signOut() }
                        }
                    } message: {
                        Text(OwnerCopy.signOutMessage)
                    }
            }
            if isDisabled {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text(Self.header)
        } footer: {
            if case .signedIn = account.state {
                Text(OwnerCopy.signOutFooter)
            }
        }
        .alert(AccountAlert.title, isPresented: isShowingAlert, presenting: alertMessage) { _ in
            Button(AccountAlert.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }

        // Only an Apple or Google account is offered deletion, never an anonymous one.
        if case let .signedIn(_, provider, _) = account.state {
            Section {
                Button(Self.deleteTitle, role: .destructive) {
                    isConfirmingDelete = true
                }
                .disabled(isDisabled)
                .confirmationDialog(Self.deleteDialogTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button(Self.deleteTitle, role: .destructive) {
                        deleteAccount(provider: provider)
                    }
                } message: {
                    Text(verbatim: "\(Self.deleteWarning) \(OwnerCopy.deletesWaitingPhotos)")
                }
            } footer: {
                Text(OwnerCopy.deleteFooter)
            }
        }
    }

    // MARK: Rows

    private func statusRow(provider: SignInProvider, email: String?) -> some View {
        HStack(spacing: Space.three) {
            if provider == .apple {
                Image(systemName: "apple.logo")
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.half) {
                Text(provider == .apple ? OwnerCopy.signedInWithApple : OwnerCopy.signedInWithGoogle)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                if let email {
                    // In full: a private relay address wraps rather than truncates.
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Flows

    private func deleteAccount(provider: SignInProvider) {
        // Deleting needs a fresh sign-in, with the same provider the account uses.
        run {
            let credential = try await SignInButtons.requestCredential(from: provider)
            try await account.deleteAccount(reauthWith: credential)
        }
    }

    /// Runs one flow at a time. Everything in these sections stays disabled until it ends.
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isDisabled else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await operation()
            } catch {
                await show(error)
            }
        }
    }

    private func show(_ error: Error) async {
        // A closed Apple or Google sheet changes nothing: no alert and no account work.
        guard let message = AccountAlert.message(for: error) else { return }
        alertMessage = message
        // A switch to an existing account that fails part-way can leave no current user at all.
        // `start()` signs in anonymously again when that happened, and finds the user when it did not.
        await account.start()
    }

    private var isShowingAlert: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    // MARK: Copy

    // TODO(owner): copy. Meaning: "Account".
    private static let header = String(localized: "Аккаунт")
    // TODO(owner): copy. Meaning: "Sign in to see your liked poems on your other devices too."
    private static let signInExplanation = String(localized: "Уи усэ ныбжьэхэр нэгъуэщ\u{04C0} телефоным къыщыплъагъун папщ\u{04C0}э хыхьэ.")
    // TODO(owner): copy. Meaning: "Sign out".
    private static let signOutTitle = String(localized: "Дэк\u{04C0}ын")
    // TODO(owner): copy. Meaning: "Delete account".
    private static let deleteTitle = String(localized: "Аккаунтыр хэгъэк\u{04C0}ыжьын")
    // TODO(owner): copy. Meaning: "Delete your account?"
    private static let deleteDialogTitle = String(localized: "Аккаунтыр хэбгъэк\u{04C0}ыжьыну п\u{04C0}эрэ?")
    // TODO(owner): copy. Meaning: "Your account and your liked poems will be deleted for good."
    private static let deleteWarning = String(localized: "Аккаунтымрэ уи усэ ныбжьэхэмрэ зэи къагъэзэжынкъым.")
}
