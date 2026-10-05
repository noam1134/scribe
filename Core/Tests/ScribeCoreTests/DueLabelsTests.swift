import Foundation
import Testing
@testable import ScribeCore

struct DueLabelsTests {
    let labels = DueLabels(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))
    let today = LocalDay(2026, 10, 5)

    @Test func relativeDayTitles() {
        #expect(labels.dayTitle(today, today: today) == "Today")
        #expect(labels.dayTitle(LocalDay(2026, 10, 6), today: today) == "Tomorrow")
        #expect(labels.dayTitle(LocalDay(2026, 10, 4), today: today) == "Yesterday")
        #expect(labels.dayTitle(LocalDay(2026, 10, 9), today: today) == "Fri 9 Oct")
        #expect(labels.dayTitle(LocalDay(2027, 1, 3), today: today) == "Sun, 3 Jan 2027")
    }

    @Test func dueText() {
        #expect(labels.due(DueDate(day: today), today: today) == "Today")
        #expect(labels.due(DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60 + 5), today: today) == "Tomorrow · 09:05")
    }
}
