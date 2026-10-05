import Foundation
import Testing
@testable import ScribeCore

struct WidgetEntryBuilderTests {
    let builder = WidgetEntryBuilder(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))
    let now = TestCalendar.monday // Mon 2026-10-05 10:00
    let midnight = TestCalendar.date(2026, 10, 6, 0, 0)

    static let work = CategorySnapshot(name: "Work", colorName: "orange", sortIndex: 0)
    static let trip = CategorySnapshot(name: "Thailand", emoji: "🇹🇭", colorName: "teal", sortIndex: 1)
    let categories = [work, trip]

    func task(_ title: String, _ day: LocalDay?, minute: Int? = nil, done: Bool = false, in category: CategorySnapshot? = work, created: Int = 0) -> ItemSnapshot {
        ItemSnapshot(title: title, kind: .task, categoryID: category?.id, due: day.map { DueDate(day: $0, minute: minute) },
                     isDone: done, createdAt: Date(timeIntervalSince1970: TimeInterval(created)))
    }

    func memo(_ title: String, _ day: LocalDay?, minute: Int? = nil, in category: CategorySnapshot? = work) -> ItemSnapshot {
        ItemSnapshot(title: title, kind: .memo, categoryID: category?.id, due: day.map { DueDate(day: $0, minute: minute) })
    }

    func timeline(_ items: [ItemSnapshot], category: UUID? = nil, at moment: Date? = nil, freshAt: Date? = nil) -> WidgetTimeline {
        builder.timeline(items: items, categories: categories, categoryID: category, now: moment ?? now, freshAt: freshAt)
    }

    func agenda(_ entry: WidgetEntry?) throws -> WidgetAgenda {
        guard case .agenda(let agenda)? = entry?.content else {
            Issue.record("expected an agenda, got \(String(describing: entry?.content))")
            throw CancellationError()
        }
        return agenda
    }

    // MARK: Content

    @Test func emptyStoreGivesAnEmptyAgendaUntilMidnight() throws {
        let plan = timeline([])
        #expect(plan.entries.map(\.date) == [now, midnight])
        #expect(plan.refreshAt == midnight)
        let first = try agenda(plan.entries.first)
        #expect(first.isEmpty)
        #expect(first.itemCount == 0)
        #expect(first.todayCount == 0)
        #expect(first.dueTaskCount == 0)
        #expect(plan.entries.first?.category == nil)
        #expect(plan.entries.first?.staleLabel == nil)
    }

    @Test func overdueTasksComeFirstAndAreLate() throws {
        let plan = timeline([
            task("today", LocalDay(2026, 10, 5)),
            task("last week", LocalDay(2026, 10, 1)),
            task("yesterday", LocalDay(2026, 10, 4)),
        ])
        let sections = try agenda(plan.entries.first).sections
        #expect(sections.map(\.title) == ["Overdue", "Today"])
        #expect(sections[0].isOverdue)
        #expect(sections[0].rows.map(\.title) == ["last week", "yesterday"])
        #expect(sections[0].rows.map(\.detail) == ["Thu 1 Oct", "Yesterday"])
        #expect(sections[0].rows.allSatisfy { $0.isLate })
        #expect(sections[1].rows.map(\.isLate) == [false])
        #expect(sections[1].rows.map(\.detail) == [nil])
    }

    @Test func memosAreNeverLateAndPastMemosDropOut() throws {
        let plan = timeline([
            memo("old memo", LocalDay(2026, 10, 4)),
            memo("8am memo", LocalDay(2026, 10, 5), minute: 8 * 60),
            memo("friday memo", LocalDay(2026, 10, 9)),
        ])
        let sections = try agenda(plan.entries.first).sections
        #expect(sections.map(\.title) == ["Today", "Fri 9 Oct"])
        let rows = sections.flatMap(\.rows)
        #expect(rows.map(\.title) == ["8am memo", "friday memo"])
        #expect(rows.map(\.kind) == [.memo, .memo])
        #expect(rows.map(\.detail) == ["08:00", nil])
        #expect(!rows.contains { $0.isLate })
    }

    @Test func rowsCarryTheirCategory() throws {
        let rows = try agenda(timeline([
            task("work", LocalDay(2026, 10, 5)),
            task("trip", LocalDay(2026, 10, 5), in: Self.trip, created: 1),
            task("orphan", LocalDay(2026, 10, 5), in: nil, created: 2),
        ]).entries.first).sections.flatMap(\.rows)
        #expect(rows.map(\.category?.name) == ["Work", "Thailand", nil])
    }

    @Test func doneTasksAndUndatedItemsAreLeftOut() throws {
        let rows = try agenda(timeline([
            task("done", LocalDay(2026, 10, 5), done: true),
            task("late but done", LocalDay(2026, 10, 1), done: true),
            task("undated", nil),
            memo("undated memo", nil),
        ]).entries.first)
        #expect(rows.isEmpty)
    }

    @Test func aCategoryWidgetShowsOnlyThatCategory() throws {
        let plan = timeline([
            task("work today", LocalDay(2026, 10, 5)),
            task("trip today", LocalDay(2026, 10, 5), in: Self.trip),
            task("trip late", LocalDay(2026, 10, 2), in: Self.trip),
        ], category: Self.trip.id)
        let entry = try #require(plan.entries.first)
        #expect(entry.category == Self.trip)
        let sections = try agenda(entry).sections
        #expect(sections.flatMap(\.rows).map(\.title) == ["trip late", "trip today"])
    }

    @Test func aDeletedCategorySaysSo() {
        let plan = timeline([task("work today", LocalDay(2026, 10, 5))], category: UUID())
        #expect(plan.entries.map(\.content) == [.categoryMissing])
        #expect(plan.entries.first?.category == nil)
        #expect(plan.refreshAt == midnight)
    }

    @Test func countsForTheSmallAndCircularFamilies() throws {
        let agenda = try agenda(timeline([
            task("late", LocalDay(2026, 10, 3)),
            task("today 1", LocalDay(2026, 10, 5)),
            task("today 2", LocalDay(2026, 10, 5), minute: 18 * 60),
            memo("today memo", LocalDay(2026, 10, 5)),
            task("tomorrow", LocalDay(2026, 10, 6)),
        ]).entries.first)
        #expect(agenda.todayCount == 3, "tasks and memos due today")
        #expect(agenda.dueTaskCount == 3, "open tasks due today plus overdue")
        #expect(agenda.itemCount == 5)
    }

    @Test func storeUnavailableRetriesSoon() {
        let plan = builder.unavailable(now: now)
        #expect(plan.entries.map(\.content) == [.storeUnavailable])
        #expect(plan.entries.map(\.date) == [now])
        #expect(plan.refreshAt == now.addingTimeInterval(15 * 60))
    }

    // MARK: Timeline

    @Test func entriesAtEachOpenTimedTaskLaterToday() {
        let plan = timeline([
            task("earlier", LocalDay(2026, 10, 5), minute: 9 * 60),
            task("later", LocalDay(2026, 10, 5), minute: 14 * 60 + 30),
            task("tonight", LocalDay(2026, 10, 5), minute: 21 * 60),
            task("duplicate time", LocalDay(2026, 10, 5), minute: 21 * 60),
            task("done later", LocalDay(2026, 10, 5), minute: 16 * 60, done: true),
            memo("memo later", LocalDay(2026, 10, 5), minute: 17 * 60),
            task("tomorrow", LocalDay(2026, 10, 6), minute: 8 * 60),
            task("other category", LocalDay(2026, 10, 5), minute: 15 * 60, in: Self.trip),
        ], category: Self.work.id)
        #expect(plan.entries.map(\.date) == [
            now,
            TestCalendar.date(2026, 10, 5, 14, 30),
            TestCalendar.date(2026, 10, 5, 21, 0),
            midnight,
        ])
    }

    @Test func aTimedTaskTurnsLateAtItsTime() throws {
        let plan = timeline([task("call", LocalDay(2026, 10, 5), minute: 14 * 60 + 30)])
        let before = try agenda(plan.entries[0]).sections.flatMap(\.rows)
        let after = try agenda(plan.entries[1]).sections.flatMap(\.rows)
        #expect(before.map(\.isLate) == [false])
        #expect(after.map(\.isLate) == [true])
        #expect(after.map(\.detail) == ["14:30"])
    }

    @Test func atMidnightTodaysOpenTasksBecomeOverdue() throws {
        let plan = timeline([
            task("today task", LocalDay(2026, 10, 5)),
            memo("today memo", LocalDay(2026, 10, 5)),
            task("tomorrow", LocalDay(2026, 10, 6)),
            task("in a week", LocalDay(2026, 10, 12)),
        ])
        let sections = try agenda(plan.entries.last).sections
        #expect(plan.entries.last?.date == midnight)
        #expect(sections.map(\.title) == ["Overdue", "Today", "Mon 12 Oct"])
        #expect(sections.map { $0.rows.map(\.title) } == [["today task"], ["tomorrow"], ["in a week"]])
        #expect(sections[0].rows.map(\.detail) == ["Yesterday"])
    }

    @Test func entriesStartFromNowLateInTheDay() {
        let late = TestCalendar.date(2026, 10, 5, 23, 59)
        let plan = timeline([task("nine", LocalDay(2026, 10, 5), minute: 9 * 60)], at: late)
        #expect(plan.entries.map(\.date) == [late, midnight])
    }

    // MARK: Data age

    @Test func freshDataHasNoAgeLabel() {
        let plan = timeline([], freshAt: now.addingTimeInterval(-30 * 60))
        #expect(plan.entries.first?.staleLabel == nil)
    }

    @Test func unknownFreshnessHasNoAgeLabel() {
        #expect(timeline([]).entries.allSatisfy { $0.staleLabel == nil })
    }

    @Test func oldDataShowsWhenItWasLastUpdated() {
        let fresh = TestCalendar.date(2026, 10, 5, 7, 5)
        let plan = timeline([], freshAt: fresh)
        #expect(plan.entries.first?.staleLabel == "Updated 07:05")
        #expect(plan.entries.last?.staleLabel == "Updated yesterday", "the midnight entry is a day later")
    }

    @Test func anEntryMarksTheMomentDataTurnsStale() {
        let fresh = TestCalendar.date(2026, 10, 5, 9, 30)
        let plan = timeline([], freshAt: fresh)
        #expect(plan.entries.map(\.date) == [now, TestCalendar.date(2026, 10, 5, 11, 30), midnight])
        #expect(plan.entries.map(\.staleLabel) == [nil, "Updated 09:30", "Updated yesterday"])
    }

    @Test func olderDataNamesTheDay() {
        let plan = timeline([], freshAt: TestCalendar.date(2026, 10, 2, 18, 0))
        #expect(plan.entries.first?.staleLabel == "Updated Fri 2 Oct")
    }

    @Test func aFutureStampCountsAsFresh() {
        let plan = timeline([], freshAt: now.addingTimeInterval(60 * 60))
        #expect(plan.entries.first?.staleLabel == nil)
    }

    // MARK: Fitting rows

    func manyItems() -> [ItemSnapshot] {
        [
            task("late 1", LocalDay(2026, 10, 1), created: 0),
            task("late 2", LocalDay(2026, 10, 2), created: 1),
            task("today 1", LocalDay(2026, 10, 5), created: 2),
            task("today 2", LocalDay(2026, 10, 5), created: 3),
            task("today 3", LocalDay(2026, 10, 5), created: 4),
            task("tomorrow 1", LocalDay(2026, 10, 6), created: 5),
            task("friday 1", LocalDay(2026, 10, 9), created: 6),
        ]
    }

    @Test func everythingFitsWithRoomToSpare() throws {
        let page = try agenda(timeline(manyItems()).entries.first).fitting(lines: 20)
        #expect(page.hiddenCount == 0)
        #expect(page.sections.map(\.title) == ["Overdue", "Today", "Tomorrow", "Fri 9 Oct"])
    }

    @Test func exactlyEnoughLinesNeedsNoMoreLine() throws {
        // 4 headers + 7 rows
        let page = try agenda(timeline(manyItems()).entries.first).fitting(lines: 11)
        #expect(page.hiddenCount == 0)
        #expect(page.sections.flatMap(\.rows).count == 7)
    }

    @Test func manyItemsLeaveALineForMore() throws {
        let page = try agenda(timeline(manyItems()).entries.first).fitting(lines: 6)
        // One line reserved for "+N more": Overdue (1 + 2), Today (1 + 1).
        #expect(page.sections.map(\.title) == ["Overdue", "Today"])
        #expect(page.sections.map { $0.rows.map(\.title) } == [["late 1", "late 2"], ["today 1"]])
        #expect(page.hiddenCount == 4)
    }

    @Test func aHeaderIsNeverShownWithoutARow() throws {
        let page = try agenda(timeline(manyItems()).entries.first).fitting(lines: 5)
        // 4 usable lines: Overdue (1 + 2) leaves one line — not enough for Today's header and a row.
        #expect(page.sections.map(\.title) == ["Overdue"])
        #expect(page.hiddenCount == 5)
    }

    @Test func tooFewLinesShowNothing() throws {
        let page = try agenda(timeline(manyItems()).entries.first).fitting(lines: 1)
        #expect(page.sections.isEmpty)
        #expect(page.hiddenCount == 7)
    }

    @Test func firstRowsFlattenTheSections() throws {
        let agenda = try agenda(timeline(manyItems()).entries.first)
        let first = agenda.firstRows(3)
        #expect(first.rows.map(\.title) == ["late 1", "late 2", "today 1"])
        #expect(first.hiddenCount == 4)
        #expect(agenda.firstRows(10).hiddenCount == 0)
    }
}
