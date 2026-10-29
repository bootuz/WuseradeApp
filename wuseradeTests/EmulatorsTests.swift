// Minimum iOS 17.
//  The debug-only `-useEmulators` switch: off unless the launch argument is given.

import Foundation
import Testing
@testable import Wuserade

struct EmulatorsTests {
    @Test func `Off without the argument`() {
        #expect(!Emulators.isRequested(in: ["/path/to/Wuserade"]))
        #expect(!Emulators.isRequested(in: []))
    }

    @Test func `Off for other arguments`() {
        #expect(!Emulators.isRequested(in: ["Wuserade", "-previewDaily", "-useEmulator", "useEmulators"]))
    }

    @Test func `On with the argument`() {
        #expect(Emulators.isRequested(in: ["Wuserade", "-useEmulators"]))
    }

    @Test func `This test run does not use the emulators`() {
        #expect(!Emulators.isRequested())
    }

    @Test func `Points at the test emulator ports`() {
        #expect(Emulators.projectID == "demo-wuserade")
        #expect(Emulators.firestorePort == 8085)
        #expect(Emulators.authPort == 9099)
        #expect(Emulators.functionsPort == 5001)
        #expect(Emulators.storagePort == 9199)
    }
}
