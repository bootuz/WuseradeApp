// Minimum iOS 17.
//  Decides when a poem on screen counts as read: shown without a break for `minimumShown`, or scrolled to its end
//  after being shown for at least `minimumAtEnd`. The reader reports what is on screen; `onRead` gets each poem once.

import Foundation
import SwiftUI

@MainActor
final class ReadTracker {
    private let minimumShown: Duration
    private let minimumAtEnd: Duration
    private let clock: any Clock<Duration>
    private let onRead: (Int) -> Void

    /// The poems already counted. A poem counts once per tracker.
    private var counted: Set<Int> = []
    /// The poem on screen now, if it has not been counted yet.
    private var current: Int?
    /// Whether the current poem's end has appeared.
    private var currentReachedEnd = false
    /// Whether the current poem has been shown for `minimumAtEnd`.
    private var currentShownLongEnoughForEnd = false
    private var timer: Task<Void, Never>?

    init(
        minimumShown: Duration = .seconds(10),
        minimumAtEnd: Duration = .seconds(3),
        clock: any Clock<Duration> = ContinuousClock(),
        onRead: @escaping (Int) -> Void
    ) {
        self.minimumShown = minimumShown
        self.minimumAtEnd = minimumAtEnd
        self.clock = clock
        self.onRead = onRead
    }

    deinit {
        timer?.cancel()
    }

    /// The poem became the one on screen. Showing another poem first stops the previous one's timer.
    func shown(_ poemId: Int) {
        guard poemId != current else { return }
        stop()
        guard !counted.contains(poemId) else { return }
        current = poemId
        timer = startTimer(for: poemId)
    }

    /// The poem left the screen. Its shown time starts again from zero when it comes back.
    func hidden(_ poemId: Int) {
        guard poemId == current else { return }
        stop()
    }

    /// The poem's end appeared on screen. Counts now if the poem has been shown long enough, or once it has, as
    /// long as it is still shown. Ignored for a poem that is not shown.
    func reachedEnd(_ poemId: Int) {
        guard poemId == current else { return }
        currentReachedEnd = true
        if currentShownLongEnoughForEnd { count(poemId) }
    }

    /// The deadlines are measured from the moment the poem was shown, so they do not drift with task scheduling.
    private func startTimer(for poemId: Int) -> Task<Void, Never> {
        let sleep = clock.sleeper()
        let atEnd = min(minimumAtEnd, minimumShown)
        let shownEnough = minimumShown
        return Task { [weak self] in
            do {
                // After each sleep, `isCancelled` comes first: a sleep can finish just before the poem is hidden and
                // shown again, and the new showing (same poem, so `current` matches) must not inherit this one's time.
                try await sleep(atEnd)
                guard !Task.isCancelled, let self, self.current == poemId else { return }
                self.currentShownLongEnoughForEnd = true
                if self.currentReachedEnd {
                    self.count(poemId)
                    return
                }
                try await sleep(shownEnough)
                guard !Task.isCancelled, self.current == poemId else { return }
                self.count(poemId)
            } catch {
                // Cancelled: the poem was hidden or another one shown.
            }
        }
    }

    private func count(_ poemId: Int) {
        stop()
        guard counted.insert(poemId).inserted else { return }
        onRead(poemId)
    }

    private func stop() {
        timer?.cancel()
        timer = nil
        current = nil
        currentReachedEnd = false
        currentShownLongEnoughForEnd = false
    }
}

private extension Clock where Duration == Swift.Duration {
    /// A function that sleeps until the given time after now, the moment `sleeper()` is called.
    func sleeper() -> @Sendable (Swift.Duration) async throws -> Void {
        let start = now
        return { offset in try await self.sleep(until: start.advanced(by: offset), tolerance: nil) }
    }
}

extension EnvironmentValues {
    /// The app's one tracker. Nil in previews and wherever no reading history is kept.
    @Entry var readTracker: ReadTracker?
}
