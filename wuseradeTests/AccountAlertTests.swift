import Foundation
import Testing
@testable import Wuserade

@MainActor
struct AccountAlertTests {
    @Test func `Cancelled shows no alert`() {
        #expect(AccountAlert.message(for: SignInError.cancelled) == nil)
    }

    @Test func `Missing configuration has its own text`() {
        #expect(
            AccountAlert.message(for: SignInError.missingConfiguration) ==
            AccountAlert.configurationMessage
        )
        #expect(AccountAlert.configurationMessage != AccountAlert.genericMessage)
    }

    @Test(arguments: [
        SignInError.missingToken,
        SignInError.noPresentingWindow,
        AccountError.notSignedIn,
        URLError(.notConnectedToInternet),
    ] as [any Error])
    func `Other errors show the generic text`(error: any Error) {
        #expect(AccountAlert.message(for: error) == AccountAlert.genericMessage, "\(error)")
    }
}
