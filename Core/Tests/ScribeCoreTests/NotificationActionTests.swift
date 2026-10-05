import Foundation
import Testing
@testable import ScribeCore

/// Spec §11: Done, +1 hour and Tomorrow on an item's notification.
struct NotificationActionTimeTests {
    let calendar = TestCalendar.jerusalem

    static let inAnHourCases: [(hour: Int, minute: Int, second: Int, expected: DueDate)] = [
        (14, 0, 0, DueDate(day: LocalDay(2026, 10, 5), minute: 15 * 60)),
        (14, 0, 20, DueDate(day: LocalDay(2026, 10, 5), minute: 15 * 60)),
        (14, 0, 59, DueDate(day: LocalDay(2026, 10, 5), minute: 15 * 60)),
        (14, 1, 0, DueDate(day: LocalDay(2026, 10, 5), minute: 15 * 60 + 5)),
        (14, 3, 0, DueDate(day: LocalDay(2026, 10, 5), minute: 15 * 60 + 5)),
        (14, 5, 0, DueDate(day: LocalDay(2026, 10, 5), minute: 15 * 60 + 5)),
        (10, 57, 0, DueDate(day: LocalDay(2026, 10, 5), minute: 12 * 60)),
        (23, 30, 0, DueDate(day: LocalDay(2026, 10, 6), minute: 30)),
        (22, 57, 30, DueDate(day: LocalDay(2026, 10, 6), minute: 0)),
    ]

    /// Now + 1 hour, seconds dropped, rounded up to the next 5 minutes.
    @Test(arguments: inAnHourCases)
    func inAnHourRoundsUpToFiveMinutes(hour: Int, minute: Int, second: Int, expected: DueDate) {
        let now = TestCalendar.date(2026, 10, 5, hour, minute).addingTimeInterval(TimeInterval(second))
        #expect(NotificationAction.dueInAnHour(from: now, calendar: calendar) == expected)
    }

    /// An hour later by the clock on the wall, not just in elapsed time,
    /// except inside the hour the autumn change repeats.
    @Test func inAnHourAcrossTheAutumnDSTChange() {
        // Israel: 02:00 IDT on 2026-10-25 becomes 01:00 IST.
        let beforeChange = TestCalendar.date(2026, 10, 25, 0, 40) // 00:40 IDT
        #expect(NotificationAction.dueInAnHour(from: beforeChange, calendar: calendar) == DueDate(day: LocalDay(2026, 10, 25), minute: 60 + 40))
        let insideRepeat = beforeChange.addingTimeInterval(3600) // 01:40 IDT; an hour later is 01:40 IST
        #expect(NotificationAction.dueInAnHour(from: insideRepeat, calendar: calendar) == DueDate(day: LocalDay(2026, 10, 25), minute: 60 + 40))
    }

    static let monday = LocalDay(2026, 10, 5)

    static let tomorrowCases: [(due: DueDate?, expected: DueDate)] = [
        // Alert fired today: tomorrow, same time.
        (DueDate(day: monday, minute: 14 * 60), DueDate(day: LocalDay(2026, 10, 6), minute: 14 * 60)),
        // An old alert acted on late: still tomorrow, not a day that has passed.
        (DueDate(day: LocalDay(2026, 10, 1), minute: 9 * 60), DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60)),
        // Moved to Friday on another device since the alert: Saturday.
        (DueDate(day: LocalDay(2026, 10, 9), minute: 9 * 60), DueDate(day: LocalDay(2026, 10, 10), minute: 9 * 60)),
        // Untimed stays untimed.
        (DueDate(day: monday), DueDate(day: LocalDay(2026, 10, 6))),
        // Date cleared since the alert: tomorrow, no time.
        (nil, DueDate(day: LocalDay(2026, 10, 6))),
    ]

    @Test(arguments: tomorrowCases)
    func tomorrowKeepsTheTime(due: DueDate?, expected: DueDate) {
        #expect(NotificationAction.dueTomorrow(after: due, today: Self.monday, calendar: calendar) == expected)
    }

    @Test func identifiersRoundTrip() {
        for action in NotificationAction.allCases {
            #expect(NotificationAction(rawValue: action.rawValue) == action)
        }
        #expect(NotificationAction(rawValue: "com.apple.UNNotificationDefaultActionIdentifier") == nil)
    }
}

@MainActor
struct NotificationActionStoreTests {
    let now = TestCalendar.monday // Mon 2026-10-05 10:00
    let calendar = TestCalendar.jerusalem

    @Test func doneCompletesTheTask() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        try NotificationAction.done.perform(itemID: id, store: store, now: now, calendar: calendar)
        #expect(store.item(id)?.isDone == true)
    }

    @Test func doneOnAMemoChangesNothing() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Dentist", kind: .memo, due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        let before = store.item(id)
        try NotificationAction.done.perform(itemID: id, store: store, now: now, calendar: calendar)
        #expect(store.item(id) == before)
    }

    @Test func inAnHourMovesTheDueTime() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        try NotificationAction.inAnHour.perform(itemID: id, store: store, now: now.addingTimeInterval(120), calendar: calendar)
        #expect(store.item(id)?.due == DueDate(day: LocalDay(2026, 10, 5), minute: 11 * 60 + 5))
        #expect(store.item(id)?.title == "Call Dan")
    }

    @Test func tomorrowMovesTheDay() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Call Dan", due: DueDate(day: LocalDay(2026, 10, 5), minute: 9 * 60)))
        try NotificationAction.tomorrow.perform(itemID: id, store: store, now: now, calendar: calendar)
        #expect(store.item(id)?.due == DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60))
    }

    /// The item was deleted on another device after the alert fired.
    @Test func aMissingItemIsIgnored() throws {
        let store = try makeStore()
        for action in NotificationAction.allCases {
            try action.perform(itemID: UUID(), store: store, now: now, calendar: calendar)
        }
        #expect(store.items(.all).isEmpty)
    }
}
