import Foundation
@testable import ScribeCore

final class TestClock {
    var now = TestCalendar.monday

    func advance(minutes: Int) {
        now = now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

@MainActor
func makeStore(clock: TestClock = TestClock()) throws -> SwiftDataItemStore {
    SwiftDataItemStore(container: try StoreFactory.inMemory(), calendar: TestCalendar.jerusalem, now: { clock.now })
}
