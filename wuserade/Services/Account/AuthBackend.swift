import FirebaseAuth
import Foundation
import GoogleSignIn

enum SignInProvider: String, Codable {
    case apple = "apple.com"
    case google = "google.com"
}

/// A credential from the Apple or Google sign-in sheet, ready for Firebase.
struct ProviderCredential {
    let provider: SignInProvider
    let credential: AuthCredential
    /// Apple only: needed to revoke the Apple token when the account is deleted.
    let appleAuthorizationCode: String?
}

/// The parts of a Firebase user the app needs.
struct AuthUserInfo: Equatable {
    let uid: String
    let isAnonymous: Bool
    /// Apple or Google, when one of them is linked.
    let provider: SignInProvider?
    let email: String?
}

enum AuthBackendError: Error {
    /// The credential already belongs to another account. Sign in to that account with the
    /// carried credential (Firebase's updated one, since an Apple ID token cannot be used twice).
    case credentialAlreadyInUse(ProviderCredential)
    /// `deleteCurrentUser(expectedUID:)` found a different user signed in, and deleted nothing.
    case currentUserMismatch
}

/// Firebase Auth, behind a protocol so `AccountManager` can be tested with a fake.
protocol AuthBackend {
    var currentUser: AuthUserInfo? { get }
    func signInAnonymously() async throws -> AuthUserInfo
    /// Links the credential to the current user, keeping its uid. Throws
    /// `AuthBackendError.credentialAlreadyInUse` when the credential belongs to another account.
    func link(_ c: ProviderCredential) async throws -> AuthUserInfo
    func signIn(with c: ProviderCredential) async throws -> AuthUserInfo
    func reauthenticate(with c: ProviderCredential) async throws
    func revokeAppleToken(authorizationCode: String) async throws
    /// Deletes the current user, which signs it out, but only when its uid is `expectedUID`.
    /// Does nothing when no one is signed in. Throws `AuthBackendError.currentUserMismatch`,
    /// deleting nothing, when someone else is.
    func deleteCurrentUser(expectedUID: String) async throws
    func signOut() throws
}

struct FirebaseAuthBackend: AuthBackend {
    private var auth: Auth { Auth.auth() }

    var currentUser: AuthUserInfo? {
        auth.currentUser.map(AuthUserInfo.init)
    }

    func signInAnonymously() async throws -> AuthUserInfo {
        AuthUserInfo(try await auth.signInAnonymously().user)
    }

    func link(_ c: ProviderCredential) async throws -> AuthUserInfo {
        let user = try signedInUser()
        do {
            return AuthUserInfo(try await user.link(with: c.credential).user)
        } catch let error as NSError
            where error.domain == AuthErrorDomain && error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
            let updated = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential
            throw AuthBackendError.credentialAlreadyInUse(
                ProviderCredential(
                    provider: c.provider,
                    credential: updated ?? c.credential,
                    appleAuthorizationCode: c.appleAuthorizationCode
                )
            )
        }
    }

    func signIn(with c: ProviderCredential) async throws -> AuthUserInfo {
        AuthUserInfo(try await auth.signIn(with: c.credential).user)
    }

    func reauthenticate(with c: ProviderCredential) async throws {
        _ = try await signedInUser().reauthenticate(with: c.credential)
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        try await auth.revokeToken(withAuthorizationCode: authorizationCode)
    }

    func deleteCurrentUser(expectedUID: String) async throws {
        guard let user = auth.currentUser else { return }
        guard user.uid == expectedUID else { throw AuthBackendError.currentUserMismatch }
        try await user.delete()
        await MainActor.run { GIDSignIn.sharedInstance.signOut() }
    }

    func signOut() throws {
        try auth.signOut()
        // So the next Google sign-in offers the account picker again.
        GIDSignIn.sharedInstance.signOut()
    }

    private func signedInUser() throws -> FirebaseAuth.User {
        guard let user = auth.currentUser else { throw AuthErrorCode.nullUser }
        return user
    }
}

extension AuthUserInfo {
    init(_ user: FirebaseAuth.User) {
        let linked = user.providerData.lazy.compactMap { info in
            SignInProvider(rawValue: info.providerID).map { (provider: $0, email: info.email) }
        }.first
        self.init(
            uid: user.uid,
            isAnonymous: user.isAnonymous,
            provider: linked?.provider,
            email: user.email ?? linked?.email
        )
    }
}
