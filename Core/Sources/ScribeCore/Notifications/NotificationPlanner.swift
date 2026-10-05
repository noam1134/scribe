import Foundation

/// Decides exactly which local notifications should be pending (spec §11):
/// an alert at each timed item's due time, and a morning summary on each of
/// the next seven days that has items. Pure: the app diffs the result against
/// what is pending and schedules the difference.
public struct NotificationPlanner: Sendable {
    /// iOS keeps at most 64 pending requests per app; leave some headroom.
    public static let requestLimit = 60
    /// Morning summaries planned ahead.
    public static let summaryDays = 7

    public var calendar: Calendar
    private let labels: DueLabels

    /// `calendar` is the device's calendar and time zone.
    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        labels = DueLabels(calendar: calendar, locale: locale)
    }

    /// Up to `limit` requests, ordered by fire date. The summaries get the
    /// budget first, then due-time alerts nearest-first.
    public func plan(
        items: [ItemSnapshot],
        categories: [CategorySnapshot],
        settings: NotificationSettings,
        now: Date,
        limit: Int = requestLimit
    ) -> [PlannedNotification] {
        guard settings.isEnabled, limit > 0 else { return [] }
        let summaries = settings.morningSummaryEnabled
            ? morningSummaries(items: items, minute: settings.morningSummaryMinute, now: now)
            : []
        let kept = Array(summaries.prefix(limit))
        let alerts = dueAlerts(items: items, categories: categories, now: now).prefix(limit - kept.count)
        // By fire date; at the same moment, summaries first, then alerts in
        // their own (creation) order.
        return (kept + alerts).enumerated()
            .sorted { ($0.element.fireDate, $0.offset) < ($1.element.fireDate, $1.offset) }
            .map(\.element)
    }

    // MARK: Due-time alerts

    /// Every open timed item (tasks and memos) still ahead, nearest first.
    private func dueAlerts(items: [ItemSnapshot], categories: [CategorySnapshot], now: Date) -> [PlannedNotification] {
        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items
            .compactMap { item -> (ItemSnapshot, Int, Date)? in
                guard !item.isDone, let due = item.due, let minute = due.minute else { return nil }
                let fireDate = due.day.date(atMinute: minute, calendar: calendar)
                return fireDate > now ? (item, minute, fireDate) : nil
            }
            .sorted { ($0.2, $0.0.createdAt, $0.0.id.uuidString) < ($1.2, $1.0.createdAt, $1.0.id.uuidString) }
            .map { item, minute, fireDate in
                let category = item.categoryID.flatMap { categoriesByID[$0] }
                let place = category.map { $0.emoji.isEmpty ? $0.name : "\($0.emoji) \($0.name)" }
                let firstLine = [labels.time(minute), place].compactMap { $0 }.joined(separator: " · ")
                let notes = item.body
                    .split(whereSeparator: \.isNewline)
                    .lazy
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
                return PlannedNotification(
                    id: PlannedNotification.identifier(forItem: item.id),
                    kind: .due(itemID: item.id),
                    category: item.kind == .task ? .task : .memo,
                    fireDate: fireDate,
                    trigger: trigger(for: fireDate),
                    title: item.title,
                    body: [firstLine, notes].compactMap { $0 }.joined(separator: "\n"),
                    threadID: item.categoryID.map { "category.\($0.uuidString)" } ?? "inbox"
                )
            }
    }

    // MARK: Morning summary

    /// The next `summaryDays` summary times after `now`, keeping only days
    /// with at least one item due. Content follows the agenda rules (§6) as
    /// of that morning, assuming nothing changes until then — every change
    /// re-plans.
    private func morningSummaries(items: [ItemSnapshot], minute: Int, now: Date) -> [PlannedNotification] {
        let today = LocalDay(now, calendar: calendar)
        let firstDay = today.date(atMinute: minute, calendar: calendar) > now ? today : today.adding(days: 1, calendar: calendar)
        return (0..<Self.summaryDays).compactMap { offset in
            let day = firstDay.adding(days: offset, calendar: calendar)
            let agenda = AgendaBuilder.build(items: items, scope: .all, now: day.date(atMinute: 12 * 60, calendar: calendar), calendar: calendar)
            guard let dayItems = agenda.days.first(where: { $0.day == day })?.items, !dayItems.isEmpty else { return nil }
            var titles = dayItems.prefix(3).map(\.title).joined(separator: ", ")
            if dayItems.count > 3 { titles += ", …" }
            let overdue = agenda.overdue.isEmpty ? nil : "Overdue: \(agenda.overdue.count)"
            let fireDate = day.date(atMinute: minute, calendar: calendar)
            return PlannedNotification(
                id: PlannedNotification.identifier(forSummaryOn: day),
                kind: .morningSummary(day),
                category: .summary,
                fireDate: fireDate,
                trigger: trigger(for: fireDate),
                title: "Today: \(dayItems.count)",
                body: [titles, overdue].compactMap { $0 }.joined(separator: "\n"),
                threadID: "summary"
            )
        }
    }

    // MARK: Trigger

    /// Wall-clock components of `date` in the device calendar. No time zone
    /// is set, so the trigger floats with the device; a time a DST jump
    /// skips comes out as the moment Foundation resolved it to.
    private func trigger(for date: Date) -> DateComponents {
        var units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        if calendar.identifier != .gregorian { units.insert(.era) }
        return calendar.dateComponents(units, from: date)
    }
}
