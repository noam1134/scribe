import Foundation
import Testing
@testable import ScribeCore

struct WindowOpenGateTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    func open(_ gate: inout WindowOpenGate, _ now: Date) -> Bool {
        gate.requestOpen(now: now)
    }

    /// A menu bar click sets a link and asks for the window; the link's
    /// observer asks again before the first window is on screen.
    @Test func oneOpenAtATime() {
        var gate = WindowOpenGate(timeout: 2)
        #expect(open(&gate, at(0)))
        #expect(!open(&gate, at(0.1)))
        #expect(!open(&gate, at(1.9)))
    }

    @Test func theWindowAppearingEndsTheRequest() {
        var gate = WindowOpenGate(timeout: 2)
        #expect(open(&gate, at(0)))
        gate.windowAppeared()
        // Closed again later: the next request opens one.
        #expect(open(&gate, at(0.5)))
    }

    /// A request that never produced a window doesn't block forever.
    @Test func aStaleRequestTimesOut() {
        var gate = WindowOpenGate(timeout: 2)
        #expect(open(&gate, at(0)))
        #expect(open(&gate, at(2)))
        #expect(!open(&gate, at(2.5)))
    }

    @Test func aClockGoingBackDoesNotBlock() {
        var gate = WindowOpenGate(timeout: 2)
        #expect(open(&gate, at(10)))
        #expect(open(&gate, at(5)))
    }
}
