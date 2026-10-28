import XCTest
@testable import Wuserade

final class AppVersionTests: XCTestCase {
    func testNilMinimumIsSupported() {
        XCTAssertTrue(AppVersion.isSupported(current: "1.4", minimum: nil))
    }

    func testEqualIsSupported() {
        XCTAssertTrue(AppVersion.isSupported(current: "1.5", minimum: "1.5"))
    }

    func testOlderIsNotSupported() {
        XCTAssertFalse(AppVersion.isSupported(current: "1.4", minimum: "1.5"))
    }

    func testNumericCompare() {
        // "1.5" is below "1.10": the parts are numbers, not text.
        XCTAssertFalse(AppVersion.isSupported(current: "1.5", minimum: "1.10"))
        XCTAssertTrue(AppVersion.isSupported(current: "1.10", minimum: "1.5"))
    }

    func testNewerMajor() {
        XCTAssertTrue(AppVersion.isSupported(current: "2.0", minimum: "1.10"))
    }

    func testPatchAboveMinimum() {
        XCTAssertTrue(AppVersion.isSupported(current: "1.5.1", minimum: "1.5"))
    }

    func testPatchBelowMinimum() {
        XCTAssertFalse(AppVersion.isSupported(current: "1.5", minimum: "1.5.1"))
    }

    func testMissingPartsCountAsZero() {
        XCTAssertTrue(AppVersion.isSupported(current: "1.5", minimum: "1.5.0"))
        XCTAssertTrue(AppVersion.isSupported(current: "1.5.0", minimum: "1.5"))
        XCTAssertFalse(AppVersion.isSupported(current: "1", minimum: "1.0.1"))
    }

    func testBlankOrMalformedMinimumIsSupported() {
        // A typo in the Firestore value must never lock everyone out.
        for minimum in ["", "  ", "abc", "1.x", "1..5", "-1.0", "1.5-beta"] {
            XCTAssertTrue(AppVersion.isSupported(current: "1.4", minimum: minimum), "minimum: \(minimum)")
        }
    }

    func testSpacesAroundMinimumAreIgnored() {
        XCTAssertFalse(AppVersion.isSupported(current: "1.4", minimum: " 1.5 "))
        XCTAssertTrue(AppVersion.isSupported(current: "1.5", minimum: " 1.5\n"))
    }

    func testCurrentIsThisBuildsVersion() {
        // The hosted tests run inside the app, so this reads the app's own Info.plist.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(AppVersion.current, version)
        XCTAssertTrue(AppVersion.isSupported(current: AppVersion.current, minimum: AppVersion.current))
    }
}
