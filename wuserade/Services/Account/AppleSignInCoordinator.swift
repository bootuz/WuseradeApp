import AuthenticationServices
import CryptoKit
import FirebaseAuth
import UIKit

/// Shows the Sign in with Apple sheet and turns the result into a Firebase credential.
/// Used both to sign in and to re-authenticate before account deletion.
@MainActor
final class AppleSignInCoordinator: NSObject {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?

    /// Throws `SignInError.cancelled` when the person closes the sheet.
    func signIn() async throws -> ProviderCredential {
        // A second tap while the sheet is up gets nothing to show.
        guard continuation == nil else { throw SignInError.cancelled }
        guard let window = UIApplication.shared.presentationWindow else { throw SignInError.noPresentingWindow }

        let nonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let authorization: ASAuthorization
        do {
            authorization = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.anchor = window
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller
                controller.performRequests()
            }
        } catch {
            throw SignInError.map(error)
        }

        guard
            let appleID = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = appleID.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else { throw SignInError.missingToken }

        return ProviderCredential(
            provider: .apple,
            credential: OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: appleID.fullName),
            appleAuthorizationCode: appleID.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    private func finish(with result: Result<ASAuthorization, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        controller = nil
        anchor = nil
        continuation?.resume(with: result)
    }

    /// A random string for the Apple request's nonce. Apple gets its SHA-256 and Firebase the
    /// raw value, which ties the identity token to this request.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        // Cryptographically secure on Apple platforms.
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< length).map { _ in charset[Int.random(in: 0 ..< charset.count, using: &generator)] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(with: .success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(with: .failure(error))
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // `signIn()` sets the anchor before the request starts.
        anchor ?? UIApplication.shared.presentationWindow ?? ASPresentationAnchor()
    }
}

extension UIApplication {
    /// The key window of the active scene, for presenting the Apple and Google sign-in sheets.
    var presentationWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState != .foregroundActive }
        return ordered.lazy.compactMap { $0.keyWindow ?? $0.windows.first }.first
    }
}
