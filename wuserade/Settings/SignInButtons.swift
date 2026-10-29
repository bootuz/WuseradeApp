// Minimum iOS 17.
//  Sign in with Apple and with Google, both signin-height and full width up to 360, and the alert for a flow that
//  fails. Settings' Account section and the sheet that asks for a sign-in before a photo is sent both show them.

import SwiftUI

struct SignInButtons: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    /// True from the tap on a button until its flow ends, the Apple or Google sheet included.
    /// `account.isBusy` only starts once the sheet is done, and Google's flow has no guard against a second tap.
    /// It belongs to the parent, so the screen around the buttons can lock and show progress from the tap too.
    @Binding var isWorking: Bool
    @State private var alertMessage: String?

    /// A flow can last until the device reconnects (writes wait for the server), so only the buttons (and what
    /// the parent chooses to lock) are locked while it runs, never the rest of the screen.
    private var isDisabled: Bool { isWorking || account.isBusy }

    var body: some View {
        VStack(spacing: Space.three) {
            AppleIDButton(style: colorScheme == .dark ? .white : .black) {
                signIn(with: .apple)
            }
            .id(colorScheme)
            .frame(height: Space.signinHeight)

            Button {
                signIn(with: .google)
            } label: {
                // Google's G from its branding kit, centred with the label like the Apple button's logo and text.
                HStack(spacing: Self.googleLogoSpacing) {
                    Image(decorative: "google-g")
                        .resizable()
                        .frame(width: Self.googleLogoSize, height: Self.googleLogoSize)
                    Text(Self.googleTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color("google-text"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, Space.four)
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
        .alert(AccountAlert.title, isPresented: isShowingAlert, presenting: alertMessage) { _ in
            Button(AccountAlert.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Flows

    private func signIn(with provider: SignInProvider) {
        run {
            let credential = try await Self.requestCredential(from: provider)
            try await account.signIn(with: credential)
        }
    }

    /// Asks Apple or Google for a credential. Deleting an account needs one too, so Settings calls this as well.
    static func requestCredential(from provider: SignInProvider) async throws -> ProviderCredential {
        switch provider {
        case .apple: return try await AppleSignInCoordinator().signIn()
        case .google: return try await GoogleSignInCoordinator().signIn()
        }
    }

    /// Runs one flow at a time. The buttons stay disabled until it ends.
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

    /// The G's size and its gap to the label, as in the buttons of Google's branding kit.
    private static let googleLogoSize: CGFloat = 20
    private static let googleLogoSpacing: CGFloat = 10

    // TODO(owner): copy. Meaning: "Sign in with Google".
    private static let googleTitle = String(localized: "Google-к\u{04C0}э хыхьэн")
}
