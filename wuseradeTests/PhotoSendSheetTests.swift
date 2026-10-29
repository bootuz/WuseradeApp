import XCTest
@testable import Wuserade

@MainActor
final class PhotoSendSheetTests: XCTestCase {
    func testBannedHasNoRetry() {
        XCTAssertEqual(
            PhotoSendSheet.failureMessage(for: PhotoSubmissionError.banned),
            PhotoSendSheet.FailureMessage(text: OwnerCopy.photoSendBanned, canRetry: false)
        )
    }

    func testOtherErrorsCanRetry() {
        let errors: [Error] = [
            PhotoSubmissionError.notSignedIn,
            URLError(.notConnectedToInternet),
            CocoaError(.fileWriteOutOfSpace),
        ]
        for error in errors {
            XCTAssertEqual(
                PhotoSendSheet.failureMessage(for: error),
                PhotoSendSheet.FailureMessage(text: OwnerCopy.photoSendFailed, canRetry: true),
                "\(error)"
            )
        }
    }
}
