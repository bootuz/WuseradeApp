import Foundation
import Testing
@testable import Wuserade

@MainActor
final class ReadTrackerTests {
    private let clock = TestClock()
    private var reads: [Int] = []

    private func makeTracker() -> ReadTracker {
        ReadTracker(clock: clock) { [weak self] in self?.reads.append($0) }
    }

    /// Moves the clock and lets the tracker's woken timers run.
    private func advance(_ duration: Duration) async {
        clock.advance(by: duration)
        await settle()
    }

    @Test func `Ten seconds shown counts once`() async {
        let tracker = makeTracker()
        tracker.shown(7)
        await advance(.seconds(9))
        #expect(reads == [])

        await advance(.seconds(1))
        #expect(reads == [7])

        await advance(.seconds(10))
        tracker.reachedEnd(7)
        tracker.hidden(7)
        tracker.shown(7)
        await advance(.seconds(10))
        #expect(reads == [7], "a poem counts once per tracker")
    }

    @Test func pagingPastWithinThreeSecondsDoesNotCount() async {
        let tracker = makeTracker()
        tracker.shown(7)
        await advance(.seconds(1))
        tracker.reachedEnd(7)
        await advance(.seconds(1))
        tracker.hidden(7)
        await advance(.seconds(20))

        #expect(reads == [])
    }

    @Test func `End after three seconds counts`() async {
        let tracker = makeTracker()
        // The end appears early: it counts once the poem has been shown for three seconds.
        tracker.shown(7)
        await advance(.seconds(1))
        tracker.reachedEnd(7)
        await advance(.seconds(1))
        #expect(reads == [])
        await advance(.seconds(1))
        #expect(reads == [7])

        // The end appears later: it counts at once.
        tracker.hidden(7)
        tracker.shown(8)
        await advance(.seconds(4))
        #expect(reads == [7])
        tracker.reachedEnd(8)
        await settle()
        #expect(reads == [7, 8])

        // The end of a poem that is not shown is ignored.
        tracker.reachedEnd(9)
        await advance(.seconds(5))
        #expect(reads == [7, 8])
    }

    @Test func `Hiding resets the shown time`() async {
        let tracker = makeTracker()
        tracker.shown(7)
        await advance(.seconds(8))
        tracker.hidden(7)
        tracker.shown(7)
        await advance(.seconds(8))
        #expect(reads == [])

        await advance(.seconds(2))
        #expect(reads == [7])
    }

    @Test func `Showing another poem stops the first one's timer`() async {
        let tracker = makeTracker()
        tracker.shown(7)
        await advance(.seconds(5))
        tracker.shown(8)
        await advance(.seconds(5))
        #expect(reads == [])
        await advance(.seconds(5))
        #expect(reads == [8])
    }
}
