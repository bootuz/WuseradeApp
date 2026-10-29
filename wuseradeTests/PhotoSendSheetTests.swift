import Foundation
import Testing
@testable import Wuserade

@MainActor
struct PhotoSendSheetTests {
    @Test func `Banned has no retry`() {
        #expect(
            PhotoSendSheet.failureMessage(for: PhotoSubmissionError.banned)
                == PhotoSendSheet.FailureMessage(text: OwnerCopy.photoSendBanned, canRetry: false)
        )
    }

    @Test(arguments: [
        PhotoSubmissionError.notSignedIn,
        URLError(.notConnectedToInternet),
        CocoaError(.fileWriteOutOfSpace),
    ] as [any Error & Sendable])
    func `Other errors can retry`(error: any Error & Sendable) {
        #expect(
            PhotoSendSheet.failureMessage(for: error)
                == PhotoSendSheet.FailureMessage(text: OwnerCopy.photoSendFailed, canRetry: true),
            "\(error)"
        )
    }
}
