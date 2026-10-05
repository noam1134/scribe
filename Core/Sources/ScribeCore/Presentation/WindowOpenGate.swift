import Foundation

/// Lets one request to open a window through at a time. Several paths can
/// ask for the Mac's main window in the same moment — a menu bar click and
/// the link it sets — and a requested window isn't on screen yet, so
/// "is there a window?" can't tell them apart. Later requests are dropped
/// until the window appears or the request is `timeout` old.
public struct WindowOpenGate: Sendable {
    public let timeout: TimeInterval
    private var requestedAt: Date?

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    /// True when the caller should open the window now.
    public mutating func requestOpen(now: Date) -> Bool {
        if let requestedAt {
            let age = now.timeIntervalSince(requestedAt)
            if age >= 0, age < timeout { return false }
        }
        requestedAt = now
        return true
    }

    /// A window is up: the next request (after it closes) opens another.
    public mutating func windowAppeared() {
        requestedAt = nil
    }
}
