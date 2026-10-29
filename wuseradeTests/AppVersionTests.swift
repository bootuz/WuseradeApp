import Foundation
import Testing
@testable import Wuserade

struct AppVersionTests {
    @Test func `Nil minimum is supported`() {
        #expect(AppVersion.isSupported(current: "1.4", minimum: nil))
    }

    @Test func `Equal is supported`() {
        #expect(AppVersion.isSupported(current: "1.5", minimum: "1.5"))
    }

    @Test func `Older is not supported`() {
        #expect(!AppVersion.isSupported(current: "1.4", minimum: "1.5"))
    }

    @Test func `Numeric compare`() {
        // "1.5" is below "1.10": the parts are numbers, not text.
        #expect(!AppVersion.isSupported(current: "1.5", minimum: "1.10"))
        #expect(AppVersion.isSupported(current: "1.10", minimum: "1.5"))
    }

    @Test func `Newer major`() {
        #expect(AppVersion.isSupported(current: "2.0", minimum: "1.10"))
    }

    @Test func `Patch above minimum`() {
        #expect(AppVersion.isSupported(current: "1.5.1", minimum: "1.5"))
    }

    @Test func `Patch below minimum`() {
        #expect(!AppVersion.isSupported(current: "1.5", minimum: "1.5.1"))
    }

    @Test func `Missing parts count as zero`() {
        #expect(AppVersion.isSupported(current: "1.5", minimum: "1.5.0"))
        #expect(AppVersion.isSupported(current: "1.5.0", minimum: "1.5"))
        #expect(!AppVersion.isSupported(current: "1", minimum: "1.0.1"))
    }

    @Test(arguments: ["", "  ", "abc", "1.x", "1..5", "-1.0", "1.5-beta"])
    func `Blank or malformed minimum is supported`(minimum: String) {
        // A typo in the Firestore value must never lock everyone out.
        #expect(AppVersion.isSupported(current: "1.4", minimum: minimum), "minimum: \(minimum)")
    }

    @Test func `Spaces around minimum are ignored`() {
        #expect(!AppVersion.isSupported(current: "1.4", minimum: " 1.5 "))
        #expect(AppVersion.isSupported(current: "1.5", minimum: " 1.5\n"))
    }

    @Test func `Current is this build's version`() {
        // The hosted tests run inside the app, so this reads the app's own Info.plist.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(AppVersion.current == version)
        #expect(AppVersion.isSupported(current: AppVersion.current, minimum: AppVersion.current))
    }
}
