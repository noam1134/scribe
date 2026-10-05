import Foundation
import Testing
@testable import ScribeCore

struct TodayAgendaTests {
    let today = LocalDay(2026, 10, 5)

    func task(_ title: String, _ day: LocalDay, minute: Int? = nil) -> ItemSnapshot {
        ItemSnapshot(title: title, due: DueDate(day: day, minute: minute))
    }

    @Test func keepsOverdueAndTodayOnly() {
        let items = [
            task("late", LocalDay(2026, 10, 2)),
            task("today 18:00", today, minute: 18 * 60),
            task("today", today),
            task("tomorrow", LocalDay(2026, 10, 6)),
        ]
        let agenda = AgendaBuilder.build(items: items, scope: .all, now: TestCalendar.monday, calendar: TestCalendar.jerusalem)
        let todays = TodayAgenda(agenda, today: today)
        #expect(todays.overdue.map(\.title) == ["late"])
        #expect(todays.today.map(\.title) == ["today", "today 18:00"])
        #expect(!todays.isEmpty)
    }

    @Test func onlyLaterDaysMeansEmpty() {
        let agenda = AgendaBuilder.build(items: [task("tomorrow", LocalDay(2026, 10, 6))], scope: .all, now: TestCalendar.monday, calendar: TestCalendar.jerusalem)
        #expect(TodayAgenda(agenda, today: today).isEmpty)
    }
}
