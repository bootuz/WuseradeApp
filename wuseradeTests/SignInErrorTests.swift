import XCTest
import AuthenticationServices
@testable import Wuserade

final class SignInErrorTests: XCTestCase {
    func testCancellationIsMapped() {
        XCTAssertEqual(SignInError.map(ASAuthorizationError(.canceled)) as? SignInError, .cancelled)
    }

    func testGoogleCancellationIsMapped() {
        // `GIDSignInError.canceled`, built from its domain and code because the test target
        // does not link GoogleSignIn.
        let error = NSError(domain: "com.google.GIDSignIn", code: -5)
        XCTAssertEqual(SignInError.map(error) as? SignInError, .cancelled)
    }

    func testOtherErrorsPassThrough() {
        let failed = SignInError.map(ASAuthorizationError(.failed))
        XCTAssertEqual((failed as? ASAuthorizationError)?.code, .failed)

        let googleKeychain = SignInError.map(NSError(domain: "com.google.GIDSignIn", code: -2)) as NSError
        XCTAssertEqual(googleKeychain.domain, "com.google.GIDSignIn")
        XCTAssertEqual(googleKeychain.code, -2)

        XCTAssertNil(SignInError.map(URLError(.notConnectedToInternet)) as? SignInError)
    }
}
