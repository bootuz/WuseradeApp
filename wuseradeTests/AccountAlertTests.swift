import XCTest
@testable import Wuserade

@MainActor
final class AccountAlertTests: XCTestCase {
    func testCancelledShowsNoAlert() {
        XCTAssertNil(AccountSection.alertMessage(for: SignInError.cancelled))
    }

    func testMissingConfigurationHasItsOwnText() {
        XCTAssertEqual(
            AccountSection.alertMessage(for: SignInError.missingConfiguration),
            AccountSection.configurationMessage
        )
        XCTAssertNotEqual(AccountSection.configurationMessage, AccountSection.genericMessage)
    }

    func testOtherErrorsShowTheGenericText() {
        let errors: [Error] = [
            SignInError.missingToken,
            SignInError.noPresentingWindow,
            AccountError.notSignedIn,
            URLError(.notConnectedToInternet),
        ]
        for error in errors {
            XCTAssertEqual(AccountSection.alertMessage(for: error), AccountSection.genericMessage, "\(error)")
        }
    }
}
