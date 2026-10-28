import AuthenticationServices
import Foundation
import GoogleSignIn

enum SignInError: Error, Equatable {
    /// The person closed the Apple or Google sheet. Not shown as an error.
    case cancelled
    /// The provider answered without the token Firebase (or Apple token revocation) needs.
    case missingToken
    /// Google sign-in is not set up: `GoogleService-Info.plist` lacks `CLIENT_ID` (the Google
    /// provider was enabled after the file was downloaded), or Info.plist lacks the
    /// `REVERSED_CLIENT_ID` URL scheme.
    case missingConfiguration
    /// There is no window to present the sign-in sheet from.
    case noPresentingWindow

    /// Turns a cancelled Apple or Google sheet into `.cancelled`. Every other error is returned unchanged.
    static func map(_ error: Error) -> Error {
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            return SignInError.cancelled
        }
        if let error = error as? GIDSignInError, error.code == .canceled {
            return SignInError.cancelled
        }
        return error
    }
}
