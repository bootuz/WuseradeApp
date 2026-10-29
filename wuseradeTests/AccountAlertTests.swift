import XCTest
@testable import Wuserade

@MainActor
final class AccountAlertTests: XCTestCase {
    func testCancelledShowsNoAlert() {
        XCTAssertNil(AccountAlert.message(for: SignInError.cancelled))
    }

    func testMissingConfigurationHasItsOwnText() {
        XCTAssertEqual(
            AccountAlert.message(for: SignInError.missingConfiguration),
            AccountAlert.configurationMessage
        )
        XCTAssertNotEqual(AccountAlert.configurationMessage, AccountAlert.genericMessage)
    }

    func testOtherErrorsShowTheGenericText() {
        let errors: [Error] = [
            SignInError.missingToken,
            SignInError.noPresentingWindow,
            AccountError.notSignedIn,
            URLError(.notConnectedToInternet),
        ]
        for error in errors {
            XCTAssertEqual(AccountAlert.message(for: error), AccountAlert.genericMessage, "\(error)")
        }
    }
}
