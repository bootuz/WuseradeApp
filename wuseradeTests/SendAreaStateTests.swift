import XCTest
@testable import Wuserade

final class SendAreaStateTests: XCTestCase {
    func testAPhotoHidesTheAreaWhateverElseIsTrue() {
        for isSignedIn in [true, false] {
            for waiting in [WaitingStatus.unchecked, .waiting, .notWaiting, .failed] {
                XCTAssertEqual(
                    SendAreaState.resolve(hasPhoto: true, isSignedIn: isSignedIn, waiting: waiting), .hidden,
                    "signed in: \(isSignedIn), waiting: \(waiting)"
                )
            }
        }
    }

    func testSignedOutReaderGetsTheButtonWhateverTheStatus() {
        for waiting in [WaitingStatus.unchecked, .waiting, .notWaiting, .failed] {
            XCTAssertEqual(SendAreaState.resolve(hasPhoto: false, isSignedIn: false, waiting: waiting), .button,
                           "waiting: \(waiting)")
        }
    }

    func testSignedInReaderWithNothingWaitingGetsTheButton() {
        XCTAssertEqual(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .notWaiting), .button)
    }

    func testSignedInReaderWithAPhotoWaitingGetsTheWaitingLine() {
        XCTAssertEqual(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .waiting), .waiting)
    }

    func testSignedInReaderWhoseCheckFailedSeesNothing() {
        XCTAssertEqual(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .failed), .hidden)
    }

    func testSignedInReaderBeforeTheCheckAnswersSeesNothing() {
        XCTAssertEqual(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .unchecked), .hidden)
    }
}
