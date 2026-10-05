import Foundation
import Testing
@testable import ScribeCore

/// Spec §11: what gets scheduled, given the items, the clock and the settings.
struct NotificationPlannerTests {
    let calendar = TestCalendar.jerusalem
    let now = TestCalendar.monday // Mon 2026-10-05 10:00, after today's 09:00 summary
    let planner = NotificationPlanner(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))

    static let alertsOnly = NotificationSettings(isEnabled: true, morningSummaryEnabled: false, morningSummaryMinute: 540)
    static let everything = NotificationSettings.iOSDefault

    func item(
        _ title: String,
        _ day: LocalDay?,
        at minute: Int? = nil,
        kind: ItemKind = .task,
        done: Bool = false,
        category: UUID? = nil,
        notes: String = "",
        created: Int = 0
    ) -> ItemSnapshot {
        ItemSnapshot(title: title, body: notes, kind: kind, categoryID: category, due: day.map { DueDate(day: $0, minute: minute) },
                     isDone: done, createdAt: Date(timeIntervalSince1970: TimeInterval(created)))
    }

    func plan(
        _ items: [ItemSnapshot],
        categories: [CategorySnapshot] = [],
        settings: NotificationSettings = alertsOnly,
        at moment: Date? = nil,
        limit: Int = NotificationPlanner.requestLimit,
        planner: NotificationPlanner? = nil
    ) -> [PlannedNotification] {
        (planner ?? self.planner).plan(items: items, categories: categories, settings: settings, now: moment ?? now, limit: limit)
    }

    func wallClock(_ components: DateComponents) -> [Int?] {
        [components.year, components.month, components.day, components.hour, components.minute]
    }

    // MARK: Due-time alerts

    @Test func timedTaskGetsOneAlertAtItsDueTime() throws {
        let task = item("Call Dan", LocalDay(2026, 10, 5), at: 14 * 60)
        let planned = plan([task])
        #expect(planned.count == 1)
        let alert = try #require(planned.first)
        #expect(alert.id == "item.\(task.id.uuidString)")
        #expect(alert.kind == .due(itemID: task.id))
        #expect(alert.itemID == task.id)
        #expect(alert.fireDate == TestCalendar.date(2026, 10, 5, 14, 0))
        #expect(wallClock(alert.trigger) == [2026, 10, 5, 14, 0])
        #expect(alert.title == "Call Dan")
        #expect(alert.category == .task)
        #expect(alert.link == .item(task.id))
    }

    /// Floating wall-clock trigger (spec §5.2): no time zone or calendar is
    /// pinned, so the system fires it at 14:00 wherever the device is.
    @Test func triggerIsFloating() throws {
        let alert = try #require(plan([item("x", LocalDay(2026, 10, 6), at: 14 * 60)]).first)
        #expect(alert.trigger.timeZone == nil)
        #expect(alert.trigger.calendar == nil)
        #expect(alert.trigger.second == nil)
        #expect(calendar.date(from: alert.trigger) == alert.fireDate)
    }

    @Test func skipsPastDoneUntimedAndUndatedItems() {
        let planned = plan([
            item("earlier today", LocalDay(2026, 10, 5), at: 9 * 60),
            item("right now", LocalDay(2026, 10, 5), at: 10 * 60),
            item("yesterday", LocalDay(2026, 10, 4), at: 18 * 60),
            item("done", LocalDay(2026, 10, 6), at: 9 * 60, done: true),
            item("untimed", LocalDay(2026, 10, 6)),
            item("undated", nil),
        ])
        #expect(planned.isEmpty)
    }

    @Test func timedMemoAlertsWithoutDone() throws {
        let memo = item("Dentist", LocalDay(2026, 10, 7), at: 8 * 60 + 15, kind: .memo)
        let alert = try #require(plan([memo]).first)
        #expect(alert.category == .memo)
        #expect(NotificationCategory.memo.actions == [.inAnHour, .tomorrow])
        #expect(NotificationCategory.task.actions == [.done, .inAnHour, .tomorrow])
        #expect(NotificationCategory.summary.actions.isEmpty)
    }

    @Test func alertBodyShowsTimeCategoryAndFirstLineOfNotes() {
        let thailand = CategorySnapshot(name: "Thailand", emoji: "🇹🇭")
        let work = CategorySnapshot(name: "Work")
        let planned = plan([
            item("Flights", LocalDay(2026, 10, 6), at: 14 * 60, category: thailand.id, notes: "\n  Bring passports  \nand visas"),
            item("Report", LocalDay(2026, 10, 6), at: 15 * 60, category: work.id),
            item("Inbox thing", LocalDay(2026, 10, 6), at: 16 * 60),
            item("Category deleted elsewhere", LocalDay(2026, 10, 6), at: 17 * 60, category: UUID()),
        ], categories: [thailand, work])
        #expect(planned.map(\.body) == ["14:00 · 🇹🇭 Thailand\nBring passports", "15:00 · Work", "16:00", "17:00"])
    }

    @Test func alertsThreadByCategory() {
        let work = CategorySnapshot(name: "Work")
        let planned = plan([
            item("a", LocalDay(2026, 10, 6), at: 14 * 60, category: work.id),
            item("b", LocalDay(2026, 10, 6), at: 15 * 60),
        ], categories: [work])
        #expect(planned.map(\.threadID) == ["category.\(work.id.uuidString)", "inbox"])
    }

    @Test func alertsAreNearestFirstWithStableTies() {
        let planned = plan([
            item("next week", LocalDay(2026, 10, 12), at: 8 * 60),
            item("tomorrow 9", LocalDay(2026, 10, 6), at: 9 * 60),
            item("today 18 newer", LocalDay(2026, 10, 5), at: 18 * 60, created: 2),
            item("today 18 older", LocalDay(2026, 10, 5), at: 18 * 60, created: 1),
            item("in March", LocalDay(2027, 3, 1), at: 7 * 60),
        ])
        #expect(planned.map(\.title) == ["today 18 older", "today 18 newer", "tomorrow 9", "next week", "in March"])
    }

    @Test func hebrewTitlesPassThrough() {
        let planned = plan([item("לקנות חלב", LocalDay(2026, 10, 6), at: 9 * 60)])
        #expect(planned.map(\.title) == ["לקנות חלב"])
    }

    // MARK: Settings

    @Test func masterSwitchOffPlansNothing() {
        let off = NotificationSettings(isEnabled: false, morningSummaryEnabled: true, morningSummaryMinute: 540)
        #expect(plan([item("x", LocalDay(2026, 10, 6), at: 9 * 60), item("y", LocalDay(2026, 10, 6))], settings: off).isEmpty)
    }

    @Test func summaryOffKeepsAlerts() {
        let planned = plan([item("timed", LocalDay(2026, 10, 6), at: 9 * 60), item("untimed", LocalDay(2026, 10, 6))])
        #expect(planned.map(\.title) == ["timed"])
    }

    // MARK: Morning summary

    func summaries(_ planned: [PlannedNotification]) -> [PlannedNotification] {
        planned.filter { $0.category == .summary }
    }

    @Test func summaryOnlyOnDaysWithItems() {
        // Today's 09:00 has passed, so the seven slots are Tue 6 … Mon 12.
        let planned = plan([
            item("today", LocalDay(2026, 10, 5)),
            item("tue", LocalDay(2026, 10, 6)),
            item("thu memo", LocalDay(2026, 10, 8), kind: .memo),
            item("next mon", LocalDay(2026, 10, 12)),
            item("next tue is outside", LocalDay(2026, 10, 13)),
            item("undated", nil),
        ], settings: Self.everything)
        #expect(planned.map(\.id) == ["summary.2026-10-06", "summary.2026-10-08", "summary.2026-10-12"])
        #expect(planned.map(\.kind) == [.morningSummary(LocalDay(2026, 10, 6)), .morningSummary(LocalDay(2026, 10, 8)), .morningSummary(LocalDay(2026, 10, 12))])
        #expect(planned.allSatisfy { $0.category == .summary && $0.link == .upcoming && $0.threadID == "summary" })
        #expect(planned.map { wallClock($0.trigger) } == [[2026, 10, 6, 9, 0], [2026, 10, 8, 9, 0], [2026, 10, 12, 9, 0]])
    }

    @Test func todaysSummaryWhenItHasNotHappenedYet() {
        let early = TestCalendar.date(2026, 10, 5, 8, 0)
        let planned = plan([
            item("today", LocalDay(2026, 10, 5)),
            item("sun is the last slot", LocalDay(2026, 10, 11)),
            item("mon is outside", LocalDay(2026, 10, 12)),
        ], settings: Self.everything, at: early)
        #expect(planned.map(\.id) == ["summary.2026-10-05", "summary.2026-10-11"])
    }

    @Test func summaryExactlyNowIsNotPlanned() {
        let nine = TestCalendar.date(2026, 10, 5, 9, 0)
        let planned = plan([item("today", LocalDay(2026, 10, 5))], settings: Self.everything, at: nine)
        #expect(planned.isEmpty)
    }

    @Test func summaryContentCountsTheDayAndOverdueTasks() throws {
        let tuesday = LocalDay(2026, 10, 6)
        let planned = plan([
            item("Pay arnona", tuesday, at: 9 * 60, created: 5),
            item("Book flights", tuesday, created: 1),
            item("Call Dan", tuesday, created: 2),
            item("Movie night", tuesday, at: 20 * 60, kind: .memo),
            item("done Tuesday", tuesday, done: true),
            // Overdue as of Tuesday: open tasks due before it, today's included.
            item("late from Sunday", LocalDay(2026, 10, 4)),
            item("due today, still open", LocalDay(2026, 10, 5), at: 9 * 60),
            item("past memo is never overdue", LocalDay(2026, 10, 4), kind: .memo),
            item("done late task", LocalDay(2026, 10, 3), done: true),
        ], settings: Self.everything)
        let summary = try #require(summaries(planned).first)
        #expect(summary.id == "summary.2026-10-06")
        #expect(summary.title == "Today: 4")
        #expect(summary.body == "Book flights, Call Dan, Pay arnona, …\nOverdue: 2")
        #expect(summary.fireDate == TestCalendar.date(2026, 10, 6, 9, 0))
    }

    @Test func shortSummaryHasNoEllipsisOrOverdueLine() throws {
        let planned = plan([
            item("One", LocalDay(2026, 10, 6), created: 1),
            item("Two", LocalDay(2026, 10, 6), created: 2),
            item("Three", LocalDay(2026, 10, 6), created: 3),
        ], settings: Self.everything)
        let summary = try #require(planned.first)
        #expect(summary.title == "Today: 3")
        #expect(summary.body == "One, Two, Three")
    }

    @Test func overdueCountGrowsDayByDay() {
        // Planned ahead as if nothing gets done: Tuesday's open task is
        // overdue on Wednesday; on Thursday Wednesday's is too.
        let planned = plan([
            item("tue", LocalDay(2026, 10, 6)),
            item("wed", LocalDay(2026, 10, 7)),
            item("thu", LocalDay(2026, 10, 8)),
        ], settings: Self.everything)
        #expect(planned.map(\.body) == ["tue", "wed\nOverdue: 1", "thu\nOverdue: 2"])
    }

    @Test func overdueTasksAloneDoNotTriggerASummary() {
        #expect(plan([item("late", LocalDay(2026, 10, 1))], settings: Self.everything).isEmpty)
    }

    @Test func summaryAtACustomTime() {
        let settings = NotificationSettings(isEnabled: true, morningSummaryEnabled: true, morningSummaryMinute: 7 * 60 + 30)
        let planned = plan([item("x", LocalDay(2026, 10, 6))], settings: settings)
        #expect(planned.map(\.fireDate) == [TestCalendar.date(2026, 10, 6, 7, 30)])
    }

    @Test func timedItemsGetBothTheSummaryAndTheirOwnAlert() {
        let planned = plan([item("Dentist", LocalDay(2026, 10, 6), at: 11 * 60)], settings: Self.everything)
        #expect(planned.map(\.id) == ["summary.2026-10-06", planned.last!.id])
        #expect(planned.map(\.category) == [.summary, .task])
        #expect(planned.first?.body == "Dentist")
    }

    // MARK: Budget

    /// `count` timed items, one per hour from tomorrow 00:00.
    func hourly(_ count: Int) -> [ItemSnapshot] {
        (0..<count).map { hour in
            item("h\(hour)", LocalDay(2026, 10, 6).adding(days: hour / 24, calendar: calendar), at: (hour % 24) * 60, created: hour)
        }
    }

    @Test func capKeepsTheNearestSixty() {
        let planned = plan(hourly(75))
        #expect(planned.count == NotificationPlanner.requestLimit)
        #expect(planned.map(\.title) == (0..<60).map { "h\($0)" })
    }

    @Test func capKeepsSevenSummariesAndFillsTheRestWithAlerts() {
        let daily = (6...12).map { item("day \($0)", LocalDay(2026, 10, $0)) }
        let planned = plan(hourly(80) + daily, settings: Self.everything)
        #expect(planned.count == 60)
        #expect(planned.filter { $0.category == .summary }.count == 7)
        #expect(planned.filter { $0.category != .summary }.map(\.title) == (0..<53).map { "h\($0)" })
    }

    @Test func outputIsSortedByFireDate() {
        let daily = (6...12).map { item("day \($0)", LocalDay(2026, 10, $0)) }
        let planned = plan(hourly(80) + daily, settings: Self.everything)
        #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
    }

    @Test func smallLimitPrefersSummaries() {
        let daily = (6...12).map { item("day \($0)", LocalDay(2026, 10, $0)) }
        let planned = plan(hourly(5) + daily, settings: Self.everything, limit: 3)
        #expect(planned.map(\.id) == ["summary.2026-10-06", "summary.2026-10-07", "summary.2026-10-08"])
        #expect(plan(hourly(5), limit: 0).isEmpty)
    }

    // MARK: Time zones and DST

    @Test func travelingKeepsWallClockTimes() throws {
        // Monday 22:30 in Jerusalem is Tuesday 03:30 in Bangkok.
        let bangkok = TestCalendar.make(timeZone: "Asia/Bangkok", firstWeekday: 1)
        let moment = TestCalendar.date(2026, 10, 5, 22, 30)
        let items = [
            item("Monday 23:00", LocalDay(2026, 10, 5), at: 23 * 60),
            item("Tuesday 14:00", LocalDay(2026, 10, 6), at: 14 * 60),
        ]
        #expect(plan(items, at: moment).map(\.title) == ["Monday 23:00", "Tuesday 14:00"])

        let inBangkok = plan(items, at: moment, planner: NotificationPlanner(calendar: bangkok, locale: Locale(identifier: "en_GB")))
        let alert = try #require(inBangkok.first)
        #expect(inBangkok.map(\.title) == ["Tuesday 14:00"])
        #expect(wallClock(alert.trigger) == [2026, 10, 6, 14, 0])
        #expect(alert.fireDate == TestCalendar.date(2026, 10, 6, 14, 0, in: bangkok))
    }

    @Test func summariesStayAtNineAcrossTheAutumnDSTChange() {
        // Israel goes back to standard time on Sunday 2026-10-25 at 02:00.
        let friday = TestCalendar.date(2026, 10, 23, 12, 0)
        let days = (24...28).map { LocalDay(2026, 10, $0) }
        let planned = plan(days.map { item("on \($0)", $0) }, settings: Self.everything, at: friday)
        #expect(planned.map { wallClock($0.trigger) } == days.map { [2026, 10, $0.day, 9, 0] as [Int?] })
        #expect(planned.map(\.fireDate) == days.map { TestCalendar.date(2026, 10, $0.day, 9, 0) })
        // 24 h apart except across the change, which is 25 h.
        let gaps = zip(planned.dropFirst(), planned).map { $0.fireDate.timeIntervalSince($1.fireDate) / 3600 }
        #expect(gaps == [25, 24, 24, 24])
    }

    @Test func repeatedHourDuringTheAutumnChangeFiresOnce() throws {
        // 01:30 happens twice on 2026-10-25 in Israel; the alert is planned once.
        let saturdayNight = TestCalendar.date(2026, 10, 24, 23, 0)
        let planned = plan([item("01:30", LocalDay(2026, 10, 25), at: 90)], at: saturdayNight)
        let alert = try #require(planned.first)
        #expect(planned.count == 1)
        #expect(wallClock(alert.trigger) == [2026, 10, 25, 1, 30])
        #expect(alert.fireDate > saturdayNight)
    }

    @Test func timeSkippedBySpringDSTFiresJustAfterTheJump() throws {
        // Israel skips 02:00–03:00 on Friday 2027-03-26.
        let thursday = TestCalendar.date(2027, 3, 25, 12, 0)
        let alert = try #require(plan([item("02:30", LocalDay(2027, 3, 26), at: 150)], at: thursday).first)
        #expect(wallClock(alert.trigger) == [2027, 3, 26, 3, 30])
        #expect(calendar.date(from: alert.trigger) == alert.fireDate)
    }

    /// The system reads the trigger in the device's calendar, so on a device
    /// set to the Hebrew calendar the components are Hebrew-calendar ones that
    /// still name the same day and time.
    @Test func nonGregorianDeviceCalendar() throws {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let planner = NotificationPlanner(calendar: hebrew, locale: Locale(identifier: "he_IL"))
        let alert = try #require(plan([item("x", LocalDay(2026, 10, 6), at: 14 * 60)], planner: planner).first)
        #expect(alert.fireDate == TestCalendar.date(2026, 10, 6, 14, 0))
        #expect(alert.trigger.year == 5787)
        #expect(hebrew.date(from: alert.trigger) == alert.fireDate)
    }

    // MARK: Identity

    @Test func replanningIsIdempotent() {
        let items = [item("a", LocalDay(2026, 10, 6), at: 9 * 60), item("b", LocalDay(2026, 10, 7))]
        let first = plan(items, settings: Self.everything)
        let second = plan(items, settings: Self.everything)
        #expect(first == second)
        #expect(first.map(\.fingerprint) == second.map(\.fingerprint))
    }

    @Test func fingerprintChangesWithWhatIsShownOrWhen() throws {
        let original = item("Call Dan", LocalDay(2026, 10, 6), at: 9 * 60)
        var renamed = original
        renamed.title = "Call Dana"
        var moved = original
        moved.due = DueDate(day: LocalDay(2026, 10, 6), minute: 10 * 60)
        let fingerprints = try [original, renamed, moved].map { try #require(plan([$0]).first).fingerprint }
        #expect(Set(fingerprints).count == 3)
        #expect(fingerprints.allSatisfy { $0.count == 16 })
    }

    @Test func stableHashIsFNV1a() {
        #expect(StableHash.fnv1a64("") == "cbf29ce484222325")
        #expect(StableHash.fnv1a64("a") == "af63dc4c8601ec8c")
        #expect(StableHash.fnv1a64("abc") == "e71fa2190541574b")
    }

    @Test func identifierHelpers() {
        let id = UUID()
        #expect(PlannedNotification.itemID(fromIdentifier: "item.\(id.uuidString)") == id)
        #expect(PlannedNotification.itemID(fromIdentifier: "summary.2026-10-06") == nil)
        #expect(PlannedNotification.itemID(fromIdentifier: "item.nope") == nil)
        #expect(PlannedNotification.isPlannerIdentifier("item.\(id.uuidString)"))
        #expect(PlannedNotification.isPlannerIdentifier("summary.2026-10-06"))
        #expect(!PlannedNotification.isPlannerIdentifier("something-else"))
    }
}
