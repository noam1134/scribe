import Foundation
import Testing
@testable import ScribeCore

struct NotificationDiffTests {
    let planner = NotificationPlanner(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))

    func plan(_ items: [ItemSnapshot]) -> [PlannedNotification] {
        let alertsOnly = NotificationSettings(isEnabled: true, morningSummaryEnabled: false, morningSummaryMinute: 540)
        return planner.plan(items: items, categories: [], settings: alertsOnly, now: TestCalendar.monday)
    }

    func timed(_ title: String, hour: Int, id: UUID = UUID()) -> ItemSnapshot {
        ItemSnapshot(id: id, title: title, due: DueDate(day: LocalDay(2026, 10, 6), minute: hour * 60))
    }

    func pending(_ planned: [PlannedNotification]) -> [NotificationDiff.Pending] {
        planned.map { NotificationDiff.Pending(id: $0.id, fingerprint: $0.fingerprint) }
    }

    @Test func everythingIsNewOnAnEmptyCenter() {
        let planned = plan([timed("a", hour: 9), timed("b", hour: 10)])
        let diff = NotificationDiff(pending: [], planned: planned)
        #expect(diff.remove.isEmpty)
        #expect(diff.add == planned)
    }

    @Test func replanningTheSameThingChangesNothing() {
        let planned = plan([timed("a", hour: 9), timed("b", hour: 10)])
        let diff = NotificationDiff(pending: pending(planned), planned: planned)
        #expect(diff.isEmpty)
    }

    @Test func changedContentIsAddedAgainUnderTheSameID() {
        let id = UUID()
        let before = plan([timed("Call Dan", hour: 9, id: id)])
        let after = plan([timed("Call Dana", hour: 9, id: id)])
        let diff = NotificationDiff(pending: pending(before), planned: after)
        #expect(diff.remove.isEmpty) // adding with the same id replaces it
        #expect(diff.add.map(\.title) == ["Call Dana"])
    }

    @Test func goneRequestsAreRemoved() {
        let keep = timed("keep", hour: 9)
        let before = plan([keep, timed("done since", hour: 10)])
        let after = plan([keep])
        let diff = NotificationDiff(pending: pending(before), planned: after)
        #expect(diff.add.isEmpty)
        #expect(diff.remove == before.filter { $0.title == "done since" }.map(\.id))
    }

    @Test func requestsWithoutAFingerprintAreReplaced() {
        let planned = plan([timed("a", hour: 9)])
        let diff = NotificationDiff(pending: planned.map { .init(id: $0.id, fingerprint: nil) }, planned: planned)
        #expect(diff.add == planned)
    }

    @Test func foreignIdentifiersAreLeftAlone() {
        let diff = NotificationDiff(pending: [.init(id: "someone-else", fingerprint: nil)], planned: [])
        #expect(diff.isEmpty)
    }

    @Test func removalsAreSorted() {
        let ids = ["summary.2026-10-09", "item.B", "item.A"]
        let diff = NotificationDiff(pending: ids.map { .init(id: $0, fingerprint: "x") }, planned: [])
        #expect(diff.remove == ["item.A", "item.B", "summary.2026-10-09"])
    }
}
