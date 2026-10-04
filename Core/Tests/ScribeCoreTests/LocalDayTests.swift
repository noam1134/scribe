import Foundation
import Testing
@testable import ScribeCore

struct LocalDayTests {
    let calendar = TestCalendar.jerusalem

    @Test func isoStringRoundTrip() {
        let day = LocalDay(2026, 3, 7)
        #expect(day.isoString == "2026-03-07")
        #expect(LocalDay(isoString: "2026-03-07") == day)
    }

    @Test(arguments: ["", "2026-3-07", "2026/03/07", "2026-13-01", "2026-00-10", "abcd-ef-gh", "2026-03-07-01",
                      "2026-02-31", "2027-02-29", "2026-+1-03", "+123-01-01", "0000-01-01", "２０２６-01-01"])
    func rejectsMalformedISOStrings(text: String) {
        #expect(LocalDay(isoString: text) == nil)
    }

    @Test func fromDateUsesCalendarTimeZone() {
        // 2026-10-05 22:30 in Jerusalem is already 2026-10-06 in Bangkok.
        let moment = TestCalendar.date(2026, 10, 5, 22, 30)
        #expect(LocalDay(moment, calendar: calendar) == LocalDay(2026, 10, 5))
        let bangkok = TestCalendar.make(timeZone: "Asia/Bangkok", firstWeekday: 1)
        #expect(LocalDay(moment, calendar: bangkok) == LocalDay(2026, 10, 6))
    }

    @Test func addingDaysCrossesMonthYearAndDST() {
        #expect(LocalDay(2026, 10, 31).adding(days: 1, calendar: calendar) == LocalDay(2026, 11, 1))
        #expect(LocalDay(2026, 12, 31).adding(days: 1, calendar: calendar) == LocalDay(2027, 1, 1))
        // Israel leaves DST on Sunday 2026-10-25.
        #expect(LocalDay(2026, 10, 24).adding(days: 2, calendar: calendar) == LocalDay(2026, 10, 26))
        #expect(LocalDay(2026, 10, 5).adding(days: -6, calendar: calendar) == LocalDay(2026, 9, 29))
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .hebrew, .japanese, .islamicUmmAlQura, .persian])
    func nonGregorianDeviceCalendarsStillProduceGregorianDays(identifier: Calendar.Identifier) {
        var deviceCalendar = Calendar(identifier: identifier)
        deviceCalendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let moment = TestCalendar.date(2026, 10, 5, 10, 0)
        let day = LocalDay(moment, calendar: deviceCalendar)
        #expect(day == LocalDay(2026, 10, 5))
        #expect(day.isoString == "2026-10-05")
        #expect(day.adding(days: 1, calendar: deviceCalendar) == LocalDay(2026, 10, 6))
        #expect(day.weekday(calendar: deviceCalendar) == 2)
        #expect(LocalDay.validated(year: 2026, month: 2, day: 29, calendar: deviceCalendar) == nil)
        #expect(LocalDay.validated(year: 2028, month: 2, day: 29, calendar: deviceCalendar) == LocalDay(2028, 2, 29))
    }

    @Test func weekdayIsSundayBased() {
        #expect(LocalDay(2026, 10, 4).weekday(calendar: calendar) == 1) // Sunday
        #expect(LocalDay(2026, 10, 5).weekday(calendar: calendar) == 2) // Monday
        #expect(LocalDay(2026, 10, 10).weekday(calendar: calendar) == 7) // Saturday
    }

    @Test func validatedRejectsImpossibleDates() {
        #expect(LocalDay.validated(year: 2026, month: 2, day: 31, calendar: calendar) == nil)
        #expect(LocalDay.validated(year: 2027, month: 2, day: 29, calendar: calendar) == nil)
        #expect(LocalDay.validated(year: 2028, month: 2, day: 29, calendar: calendar) == LocalDay(2028, 2, 29))
        #expect(LocalDay.validated(year: 2026, month: 13, day: 1, calendar: calendar) == nil)
    }

    @Test func ordering() {
        #expect(LocalDay(2026, 9, 30) < LocalDay(2026, 10, 1))
        #expect(LocalDay(2025, 12, 31) < LocalDay(2026, 1, 1))
    }
}

struct DueDateTests {
    @Test func untimedSortsBeforeTimedOnSameDay() {
        let day = LocalDay(2026, 10, 5)
        #expect(DueDate(day: day) < DueDate(day: day, minute: 0))
        #expect(DueDate(day: day, minute: 540) < DueDate(day: day, minute: 600))
        #expect(DueDate(day: day, minute: 1439) < DueDate(day: LocalDay(2026, 10, 6)))
        #expect(!(DueDate(day: day) < DueDate(day: day)))
    }
}
