import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

/// Shows the Google sign-in flow and turns the result into a Firebase credential.
/// Used both to sign in and to re-authenticate before account deletion.
@MainActor
final class GoogleSignInCoordinator {
    /// Throws `SignInError.cancelled` when the person closes the flow, and
    /// `SignInError.missingConfiguration` when `GoogleService-Info.plist` has no `CLIENT_ID` or
    /// Info.plist lacks its `REVERSED_CLIENT_ID` URL scheme.
    func signIn() async throws -> ProviderCredential {
        // GoogleSignIn raises an Objective-C exception (a crash) for either, so check first.
        guard
            let clientID = FirebaseApp.app()?.options.clientID,
            Self.hasCallbackURLScheme(for: clientID)
        else { throw SignInError.missingConfiguration }
        guard let root = UIApplication.shared.presentationWindow?.rootViewController else {
            throw SignInError.noPresentingWindow
        }
        // Start from the window's root, then step up to whatever it presents (e.g. the Settings sheet).
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        // Only the token strings leave the callback, which runs on the main queue.
        let tokens: (idToken: String, accessToken: String) = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error {
                    continuation.resume(throwing: SignInError.map(error))
                } else if let user = result?.user, let idToken = user.idToken?.tokenString {
                    continuation.resume(returning: (idToken, user.accessToken.tokenString))
                } else {
                    continuation.resume(throwing: SignInError.missingToken)
                }
            }
        }

        return ProviderCredential(
            provider: .google,
            credential: GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken),
            appleAuthorizationCode: nil
        )
    }

    /// Whether Info.plist registers the reversed client ID (`com.googleusercontent.apps.…`)
    /// as a URL scheme, which Google redirects back to.
    private static func hasCallbackURLScheme(for clientID: String) -> Bool {
        let expected = clientID.split(separator: ".").reversed().joined(separator: ".").lowercased()
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .contains { $0.lowercased() == expected }
    }
}
