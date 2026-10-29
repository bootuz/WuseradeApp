import Foundation
import Testing
import AuthenticationServices
@testable import Wuserade

struct SignInErrorTests {
    @Test func `Cancellation is mapped`() {
        #expect(SignInError.map(ASAuthorizationError(.canceled)) as? SignInError == .cancelled)
    }

    @Test func `Google cancellation is mapped`() {
        // `GIDSignInError.canceled`, built from its domain and code because the test target
        // does not link GoogleSignIn.
        let error = NSError(domain: "com.google.GIDSignIn", code: -5)
        #expect(SignInError.map(error) as? SignInError == .cancelled)
    }

    @Test func `Other errors pass through`() {
        let failed = SignInError.map(ASAuthorizationError(.failed))
        #expect((failed as? ASAuthorizationError)?.code == .failed)

        let googleKeychain = SignInError.map(NSError(domain: "com.google.GIDSignIn", code: -2)) as NSError
        #expect(googleKeychain.domain == "com.google.GIDSignIn")
        #expect(googleKeychain.code == -2)

        #expect(SignInError.map(URLError(.notConnectedToInternet)) as? SignInError == nil)
    }
}
