import Foundation
import Testing
@testable import ScribeCore

/// Today is Monday 2026-10-05.
struct DatePresetTests {
    let today = LocalDay(2026, 10, 5)

    @Test func presetsPickTheirDay() {
        let calendar = TestCalendar.jerusalem
        #expect(DatePreset.today.day(today: today, calendar: calendar) == today)
        #expect(DatePreset.tomorrow.day(today: today, calendar: calendar) == LocalDay(2026, 10, 6))
        #expect(DatePreset.nextWeek.day(today: today, calendar: calendar) == LocalDay(2026, 10, 11)) // Sunday
    }

    @Test func nextWeekFollowsTheDevicesFirstWeekday() {
        let mondayFirst = TestCalendar.make(timeZone: "Europe/London", firstWeekday: 2)
        #expect(DatePreset.nextWeek.day(today: today, calendar: mondayFirst) == LocalDay(2026, 10, 12))
    }

    @Test func applyingKeepsTheTime() {
        let calendar = TestCalendar.jerusalem
        let due = DueDate(day: LocalDay(2026, 10, 1), minute: 18 * 60)
        #expect(DatePreset.tomorrow.applied(to: due, today: today, calendar: calendar) == DueDate(day: LocalDay(2026, 10, 6), minute: 18 * 60))
        #expect(DatePreset.today.applied(to: nil, today: today, calendar: calendar) == DueDate(day: today))
    }
}
