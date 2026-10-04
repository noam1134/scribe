import Foundation

enum TestCalendar {
    /// Gregorian, Asia/Jerusalem, week starts Sunday — the author's setup.
    static let jerusalem: Calendar = make(timeZone: "Asia/Jerusalem", firstWeekday: 1)

    static func make(timeZone: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// A wall-clock moment in Jerusalem.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, in calendar: Calendar = jerusalem) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Monday 2026-10-05 10:00 Jerusalem — "now" in most tests.
    static let monday = date(2026, 10, 5, 10, 0)
}
