import AuthenticationServices
import SFSafeSymbols
import SwiftUI

/// The account part of Settings. While the account is anonymous (or there is none yet) it offers
/// Apple and Google sign-in; once signed in it shows who is signed in and offers sign-out and
/// account deletion.
struct AccountSection: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    /// True from the tap on a button until its flow ends, the Apple or Google sheet included.
    /// `account.isBusy` only starts once the sheet is done, and Google's flow has no guard against a second tap.
    @State private var isWorking = false
    @State private var isConfirmingDelete = false
    @State private var alertMessage: String?

    /// A flow can last until the device reconnects (writes wait for the server), so only this section
    /// is locked while it runs, never the rest of Settings.
    private var isDisabled: Bool { isWorking || account.isBusy }

    var body: some View {
        Section {
            statusRow
                .alert(Self.alertTitle, isPresented: isShowingAlert, presenting: alertMessage) { _ in
                    Button(Self.okTitle, role: .cancel) {}
                } message: { message in
                    Text(message)
                }

            switch account.state {
            case .signedOut, .anonymous:
                signInButtons
            case let .signedIn(_, provider, _):
                signedInButtons(provider: provider)
            }

            if isDisabled {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text(Self.header)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var statusRow: some View {
        switch account.state {
        case .signedOut, .anonymous:
            Text(Self.signInExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .signedIn(_, provider, email):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.headline)
                    if let email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemSymbol: provider.symbol)
            }
        }
    }

    @ViewBuilder
    private var signInButtons: some View {
        AppleIDButton(style: colorScheme == .dark ? .white : .black) {
            signIn(with: .apple)
        }
        .id(colorScheme)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)

        Button {
            signIn(with: .google)
        } label: {
            Label(Self.googleTitle, systemSymbol: SFSymbol.gCircleFill)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: AppleIDButton.cornerRadius).stroke(.secondary))
                .contentShape(RoundedRectangle(cornerRadius: AppleIDButton.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    @ViewBuilder
    private func signedInButtons(provider: SignInProvider) -> some View {
        Button(Self.signOutTitle) {
            run { try await account.signOut() }
        }
        .disabled(isDisabled)

        // Only an Apple or Google account is offered deletion, never an anonymous one.
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

    /// Runs one flow at a time. Everything in this section stays disabled until it ends.
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
    static let configurationMessage = "Хыхьэныр иджыри хузэфэкlыркъым."
    // TODO(owner): copy. Meaning: "Something went wrong. Check your internet connection and try again."
    static let genericMessage = "Щыуагъэ къыщыхъуащ. Интернетыр къэпщытэжи аргуэру еlэ."

    // MARK: Copy

    // TODO(owner): copy. Meaning: "Account".
    private static let header = "Аккаунт"
    // TODO(owner): copy. Meaning: "Sign in to see your liked poems on your other devices too."
    private static let signInExplanation = "Уи усэ ныбжьэхэр нэгъуэщl телефоным къыщыплъагъун папщlэ хыхьэ."
    // TODO(owner): copy. Meaning: "Sign in with Google".
    private static let googleTitle = "Google-къэ хыхьэн"
    // TODO(owner): copy. Meaning: "Sign out".
    private static let signOutTitle = "Дэкlын"
    // TODO(owner): copy. Meaning: "Delete account".
    private static let deleteTitle = "Аккаунтыр хэгъэкlыжьын"
    // TODO(owner): copy. Meaning: "Delete your account?"
    private static let deleteDialogTitle = "Аккаунтыр хэбгъэкlыжьыну пlэрэ?"
    // TODO(owner): copy. Meaning: "Your account and your liked poems will be deleted for good."
    private static let deleteWarning = "Аккаунтымрэ уи усэ ныбжьэхэмрэ зэи къагъэзэжынкъым."
    // TODO(owner): copy. Meaning: "Error".
    private static let alertTitle = "Щыуагъэ"
    // TODO(owner): copy. Meaning: "OK".
    private static let okTitle = "Хъунщ"
}

// MARK: - Provider names

private extension SignInProvider {
    /// Brand names, so they are not translated.
    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        }
    }

    var symbol: SFSymbol {
        switch self {
        case .apple: return .appleLogo
        case .google: return .gCircleFill
        }
    }
}

// MARK: - Sign in with Apple button

/// The system "Sign in with Apple" button, so it looks the way Apple requires. Its tap goes to `action`
/// instead of starting a request of its own: `AppleSignInCoordinator` runs the request.
private struct AppleIDButton: UIViewRepresentable {
    static let cornerRadius: CGFloat = 10

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
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 280, height: 44))
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }
}

#if DEBUG
#Preview("Anonymous") {
    List { AccountSection() }
        .environment(AccountManager.preview())
        .tint(.primary)
}

#Preview("Signed in") {
    SignedInPreview()
}

private struct SignedInPreview: View {
    @State private var account = AccountManager.preview(
        user: AuthUserInfo(uid: "preview", isAnonymous: false, provider: .apple, email: "name@example.com")
    )

    var body: some View {
        List { AccountSection() }
            .environment(account)
            .tint(.primary)
            .task { await account.start() }
    }
}
#endif
