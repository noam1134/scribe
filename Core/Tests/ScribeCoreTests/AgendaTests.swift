import Foundation
import Testing
@testable import ScribeCore

struct AgendaTests {
    let calendar = TestCalendar.jerusalem
    let now = TestCalendar.monday // Mon 2026-10-05 10:00

    func task(_ title: String, _ day: LocalDay?, minute: Int? = nil, done: Bool = false, category: UUID? = nil, created: Int = 0) -> ItemSnapshot {
        ItemSnapshot(title: title, kind: .task, categoryID: category, due: day.map { DueDate(day: $0, minute: minute) }, isDone: done,
                     createdAt: Date(timeIntervalSince1970: TimeInterval(created)))
    }

    func memo(_ title: String, _ day: LocalDay?) -> ItemSnapshot {
        ItemSnapshot(title: title, kind: .memo, due: day.map { DueDate(day: $0) })
    }

    func build(_ items: [ItemSnapshot], scope: CategoryScope = .all, at moment: Date? = nil, calendar: Calendar? = nil) -> Agenda {
        AgendaBuilder.build(items: items, scope: scope, now: moment ?? now, calendar: calendar ?? self.calendar)
    }

    @Test func overdueHoldsOnlyOpenPastTasks() {
        let agenda = build([
            task("late task", LocalDay(2026, 10, 3)),
            task("later late task", LocalDay(2026, 10, 4)),
            task("late but done", LocalDay(2026, 10, 3), done: true),
            memo("past memo", LocalDay(2026, 10, 3)),
        ])
        #expect(agenda.overdue.map(\.title) == ["late task", "later late task"])
        #expect(agenda.days.isEmpty)
    }

    @Test func timedTaskEarlierTodayIsTodayNotOverdue() {
        let agenda = build([task("9am today", LocalDay(2026, 10, 5), minute: 9 * 60)])
        #expect(agenda.overdue.isEmpty)
        #expect(agenda.days.map(\.day) == [LocalDay(2026, 10, 5)])
    }

    @Test func dayGroupsCoverTodayThroughSixDaysAhead() {
        let agenda = build([
            task("today", LocalDay(2026, 10, 5)),
            memo("day 6", LocalDay(2026, 10, 11)),
            task("day 7 is outside", LocalDay(2026, 10, 12)),
            task("undated", nil),
            task("done today", LocalDay(2026, 10, 5), done: true),
        ])
        #expect(agenda.days.map(\.day) == [LocalDay(2026, 10, 5), LocalDay(2026, 10, 11)])
        #expect(agenda.days.flatMap(\.items).map(\.title) == ["today", "day 6"])
    }

    @Test func withinADayUntimedComeFirstThenByTime() {
        let day = LocalDay(2026, 10, 6)
        let agenda = build([
            task("14:00", day, minute: 14 * 60, created: 1),
            task("untimed newer", day, created: 3),
            task("09:00", day, minute: 9 * 60, created: 2),
            task("untimed older", day, created: 0),
        ])
        #expect(agenda.days.first?.items.map(\.title) == ["untimed older", "untimed newer", "09:00", "14:00"])
    }

    @Test func scopeFiltersByCategory() {
        let thailand = UUID()
        let agenda = build([
            task("flights", LocalDay(2026, 10, 6), category: thailand),
            task("report", LocalDay(2026, 10, 6)),
            task("late visa", LocalDay(2026, 10, 1), category: thailand),
        ], scope: .category(thailand))
        #expect(agenda.overdue.map(\.title) == ["late visa"])
        #expect(agenda.days.flatMap(\.items).map(\.title) == ["flights"])
    }

    @Test func emptyAgenda() {
        #expect(build([]).isEmpty)
        #expect(build([task("undated", nil)]).isEmpty)
    }

    @Test func midnightTurnsYesterdayIntoOverdue() {
        let items = [task("due Monday", LocalDay(2026, 10, 5))]
        let lateMonday = TestCalendar.date(2026, 10, 5, 23, 59)
        let tuesday = TestCalendar.date(2026, 10, 6, 0, 0)
        #expect(build(items, at: lateMonday).days.map(\.day) == [LocalDay(2026, 10, 5)])
        #expect(build(items, at: tuesday).overdue.map(\.title) == ["due Monday"])
    }

    @Test func windowIsCorrectAcrossDSTChange() {
        // Israel leaves DST on Sunday 2026-10-25.
        let saturdayNight = TestCalendar.date(2026, 10, 24, 23, 30)
        let agenda = build([
            task("sunday", LocalDay(2026, 10, 25)),
            task("last day in window", LocalDay(2026, 10, 30)),
            task("first day outside", LocalDay(2026, 10, 31)),
        ], at: saturdayNight)
        #expect(agenda.days.map(\.day) == [LocalDay(2026, 10, 25), LocalDay(2026, 10, 30)])
    }

    @Test func travelingUsesTheDevicesCurrentDay() {
        // 22:30 Monday in Jerusalem is 02:30 Tuesday in Bangkok: Monday's task is overdue there.
        let bangkok = TestCalendar.make(timeZone: "Asia/Bangkok", firstWeekday: 1)
        let moment = TestCalendar.date(2026, 10, 5, 22, 30)
        let items = [task("Monday task", LocalDay(2026, 10, 5))]
        #expect(build(items, at: moment).overdue.isEmpty)
        #expect(build(items, at: moment, calendar: bangkok).overdue.map(\.title) == ["Monday task"])
    }
}

@MainActor
struct StoreAgendaTests {
    @Test func storeAgendaUsesStoredItems() throws {
        let store = try makeStore()
        let id = try store.addItem(ItemDraft(title: "Flights", due: DueDate(day: LocalDay(2026, 10, 9))))
        try store.addItem(ItemDraft(title: "Undated"))
        let agenda = store.agenda(.all, now: TestCalendar.monday)
        #expect(agenda.days.flatMap(\.items).map(\.id) == [id])
    }
}
