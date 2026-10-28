// Minimum iOS 17.
//  Аккаунт, the first sections of Settings. While the account is anonymous (or there is none yet): one line on
//  why to sign in, then Sign in with Apple and Google, both signin-height and full width up to 360. Once signed
//  in: the method and the email, Sign out with its confirmation, and a separate section for deleting the account.
//  The strings are the owner's placeholders from the Firebase work; the ones in brackets are still open.

import AuthenticationServices
import SwiftUI

struct AccountSection: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    /// True from the tap on a button until its flow ends, the Apple or Google sheet included.
    /// `account.isBusy` only starts once the sheet is done, and Google's flow has no guard against a second tap.
    @State private var isWorking = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var alertMessage: String?

    /// A flow can last until the device reconnects (writes wait for the server), so only these sections
    /// are locked while it runs, never the rest of Settings.
    private var isDisabled: Bool { isWorking || account.isBusy }

    var body: some View {
        Section {
            switch account.state {
            case .signedOut, .anonymous:
                VStack(alignment: .leading, spacing: Space.three) {
                    Text(Self.signInExplanation)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    signInButtons
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
        .alert(Self.alertTitle, isPresented: isShowingAlert, presenting: alertMessage) { _ in
            Button(Self.okTitle, role: .cancel) {}
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
                    Text(Self.deleteWarning)
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

    private var signInButtons: some View {
        VStack(spacing: Space.three) {
            AppleIDButton(style: colorScheme == .dark ? .white : .black) {
                signIn(with: .apple)
            }
            .id(colorScheme)
            .frame(height: Space.signinHeight)

            Button {
                signIn(with: .google)
            } label: {
                // The official G from Google's branding kit goes before the label once the owner adds it.
                Text(Self.googleTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color("google-text"))
                    .frame(maxWidth: .infinity)
                    .frame(height: Space.signinHeight)
                    .background(Color("google-fill"), in: .capsule)
                    .overlay(Capsule().stroke(Color("google-stroke")))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    // MARK: Flows

    private func signIn(with provider: SignInProvider) {
        run {
            let credential = try await requestCredential(from: provider)
            try await account.signIn(with: credential)
        }
    }

    private func deleteAccount(provider: SignInProvider) {
        // Deleting needs a fresh sign-in, with the same provider the account uses.
        run {
            let credential = try await requestCredential(from: provider)
            try await account.deleteAccount(reauthWith: credential)
        }
    }

    private func requestCredential(from provider: SignInProvider) async throws -> ProviderCredential {
        switch provider {
        case .apple: return try await AppleSignInCoordinator().signIn()
        case .google: return try await GoogleSignInCoordinator().signIn()
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
        guard let message = Self.alertMessage(for: error) else { return }
        alertMessage = message
        // A switch to an existing account that fails part-way can leave no current user at all.
        // `start()` signs in anonymously again when that happened, and finds the user when it did not.
        await account.start()
    }

    private var isShowingAlert: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    // MARK: Alert text

    /// The text of the alert for a failed flow, or nil when nothing should be shown (the person closed the sheet).
    static func alertMessage(for error: Error) -> String? {
        switch error as? SignInError {
        case .cancelled?: return nil
        case .missingConfiguration?: return configurationMessage
        default: return genericMessage
        }
    }

    // TODO(owner): copy. Meaning: "Signing in isn't available yet."
    static let configurationMessage = String(localized: "Хыхьэныр иджыри хузэфэк\u{04C0}ыркъым.")
    // TODO(owner): copy. Meaning: "Something went wrong. Check your internet connection and try again."
    static let genericMessage = String(localized: "Щыуагъэ къыщыхъуащ. Интернетыр къэпщытэжи аргуэру е\u{04C0}э.")

    // MARK: Copy

    // TODO(owner): copy. Meaning: "Account".
    private static let header = String(localized: "Аккаунт")
    // TODO(owner): copy. Meaning: "Sign in to see your liked poems on your other devices too."
    private static let signInExplanation = String(localized: "Уи усэ ныбжьэхэр нэгъуэщ\u{04C0} телефоным къыщыплъагъун папщ\u{04C0}э хыхьэ.")
    // TODO(owner): copy. Meaning: "Sign in with Google".
    private static let googleTitle = String(localized: "Google-к\u{04C0}э хыхьэн")
    // TODO(owner): copy. Meaning: "Sign out".
    private static let signOutTitle = String(localized: "Дэк\u{04C0}ын")
    // TODO(owner): copy. Meaning: "Delete account".
    private static let deleteTitle = String(localized: "Аккаунтыр хэгъэк\u{04C0}ыжьын")
    // TODO(owner): copy. Meaning: "Delete your account?"
    private static let deleteDialogTitle = String(localized: "Аккаунтыр хэбгъэк\u{04C0}ыжьыну п\u{04C0}эрэ?")
    // TODO(owner): copy. Meaning: "Your account and your liked poems will be deleted for good."
    private static let deleteWarning = String(localized: "Аккаунтымрэ уи усэ ныбжьэхэмрэ зэи къагъэзэжынкъым.")
    // TODO(owner): copy. Meaning: "Error".
    private static let alertTitle = String(localized: "Щыуагъэ")
    // TODO(owner): copy. Meaning: "OK".
    private static let okTitle = String(localized: "Хъунщ")
}

// MARK: - Sign in with Apple button

/// The system "Sign in with Apple" button, so it looks the way Apple requires. Its tap goes to `action`
/// instead of starting a request of its own: `AppleSignInCoordinator` runs the request, which SwiftUI's
/// `SignInWithAppleButton` cannot hand over.
private struct AppleIDButton: UIViewRepresentable {
    static let cornerRadius: CGFloat = 25

    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: style)
        button.cornerRadius = Self.cornerRadius
        let coordinator = context.coordinator
        button.addAction(UIAction { _ in coordinator.action() }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }

    /// Fills the width it is offered, which the UIKit button would not do by itself.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ASAuthorizationAppleIDButton, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 280, height: Space.signinHeight))
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }
}
