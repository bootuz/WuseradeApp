import Testing
@testable import Wuserade

struct SendAreaStateTests {
    @Test(arguments: [true, false], [WaitingStatus.unchecked, .waiting, .notWaiting, .failed])
    func `A photo hides the area whatever else is true`(isSignedIn: Bool, waiting: WaitingStatus) {
        #expect(
            SendAreaState.resolve(hasPhoto: true, isSignedIn: isSignedIn, waiting: waiting) == .hidden,
            "signed in: \(isSignedIn), waiting: \(waiting)"
        )
    }

    @Test(arguments: [WaitingStatus.unchecked, .waiting, .notWaiting, .failed])
    func `Signed out reader gets the button whatever the status`(waiting: WaitingStatus) {
        #expect(SendAreaState.resolve(hasPhoto: false, isSignedIn: false, waiting: waiting) == .button,
                "waiting: \(waiting)")
    }

    @Test func `Signed in reader with nothing waiting gets the button`() {
        #expect(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .notWaiting) == .button)
    }

    @Test func `Signed in reader with a photo waiting gets the waiting line`() {
        #expect(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .waiting) == .waiting)
    }

    @Test func `Signed in reader whose check failed sees nothing`() {
        #expect(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .failed) == .hidden)
    }

    @Test func `Signed in reader before the check answers sees nothing`() {
        #expect(SendAreaState.resolve(hasPhoto: false, isSignedIn: true, waiting: .unchecked) == .hidden)
    }
}
