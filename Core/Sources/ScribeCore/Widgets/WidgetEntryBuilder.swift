import Foundation

/// One item as a widget shows it.
public struct WidgetRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let kind: ItemKind
    /// nil = Inbox.
    public let category: CategorySnapshot?
    /// The time ("09:30") of a timed item; the due day ("Yesterday") of an
    /// overdue task.
    public let detail: String?
    /// A task that should be done by now: overdue, or timed earlier today.
    public let isLate: Bool
}

/// "Overdue", "Today", "Tomorrow", "Fri 9 Oct" and their rows.
public struct WidgetSection: Identifiable, Hashable, Sendable {
    /// "overdue" or the day as "yyyy-MM-dd".
    public let id: String
    public let title: String
    public let isOverdue: Bool
    public let rows: [WidgetRow]
}

/// The agenda (spec §6) shaped for widgets.
public struct WidgetAgenda: Hashable, Sendable {
    public let sections: [WidgetSection]
    /// Items due today, tasks and memos (the small widget's headline).
    public let todayCount: Int
    /// Open tasks due today plus overdue ones (the lock-screen circle).
    public let dueTaskCount: Int

    public var itemCount: Int { sections.reduce(0) { $0 + $1.rows.count } }
    public var isEmpty: Bool { sections.isEmpty }

    public struct Page: Hashable, Sendable {
        public let sections: [WidgetSection]
        /// Rows left out, for "+N more".
        public let hiddenCount: Int
    }

    public struct Rows: Hashable, Sendable {
        public let rows: [WidgetRow]
        public let hiddenCount: Int
    }

    /// What fits in `lines` lines when a section header and a row take one
    /// line each. When something doesn't fit, one line is kept free for
    /// "+N more". A header is never shown without a row under it.
    public func fitting(lines: Int) -> Page {
        let everything = layout(lines: lines)
        return everything.hiddenCount == 0 ? everything : layout(lines: lines - 1)
    }

    /// The first rows across all sections, for families without headers.
    public func firstRows(_ count: Int) -> Rows {
        let rows = Array(sections.flatMap(\.rows).prefix(max(count, 0)))
        return Rows(rows: rows, hiddenCount: itemCount - rows.count)
    }

    private func layout(lines: Int) -> Page {
        var remaining = lines
        var shown: [WidgetSection] = []
        for section in sections {
            guard remaining >= 2 else { break }
            let rows = Array(section.rows.prefix(remaining - 1))
            shown.append(WidgetSection(id: section.id, title: section.title, isOverdue: section.isOverdue, rows: rows))
            remaining -= 1 + rows.count
        }
        let shownCount = shown.reduce(0) { $0 + $1.rows.count }
        return Page(sections: shown, hiddenCount: itemCount - shownCount)
    }
}

/// What a widget shows at one moment.
public struct WidgetEntry: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case agenda(WidgetAgenda)
        /// The widget's category was deleted.
        case categoryMissing
        /// The store couldn't be opened (spec §13).
        case storeUnavailable
    }

    public let date: Date
    /// The widget's category; nil = all categories.
    public let category: CategorySnapshot?
    public let content: Content
    /// "Updated 09:14" once the data may be out of date (spec §18): the app
    /// hasn't synced for a while, so items added elsewhere may be missing.
    public let staleLabel: String?
}

public struct WidgetTimeline: Hashable, Sendable {
    public let entries: [WidgetEntry]
    /// When WidgetKit should ask for a new timeline.
    public let refreshAt: Date
}

/// Turns store contents into widget timeline entries (spec §10.2): one now,
/// one when each open timed task falls due later today, one when the data
/// turns stale, and one at the next local midnight, when the days roll over.
public struct WidgetEntryBuilder: Sendable {
    /// Data older than this gets an "Updated …" label.
    public static let staleAfter: TimeInterval = 2 * 60 * 60
    /// How soon to try again after the store failed to open.
    public static let retryAfter: TimeInterval = 15 * 60

    public var calendar: Calendar
    public var labels: DueLabels

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.labels = DueLabels(calendar: calendar, locale: locale)
    }

    /// - Parameters:
    ///   - categoryID: the widget's configured category; nil = all.
    ///   - freshAt: when the app last knew the store was up to date; nil = unknown (no label).
    public func timeline(items: [ItemSnapshot], categories: [CategorySnapshot], categoryID: UUID?, now: Date, freshAt: Date?) -> WidgetTimeline {
        let today = LocalDay(now, calendar: calendar)
        let midnight = today.adding(days: 1, calendar: calendar).date(calendar: calendar)
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let scope: CategoryScope
        var category: CategorySnapshot?
        if let categoryID {
            guard let configured = byID[categoryID] else {
                let entry = WidgetEntry(date: now, category: nil, content: .categoryMissing, staleLabel: nil)
                return WidgetTimeline(entries: [entry], refreshAt: midnight)
            }
            scope = .category(categoryID)
            category = configured
        } else {
            scope = .all
        }

        var dates: Set<Date> = [now, midnight]
        for item in items where item.kind == .task && !item.isDone {
            guard let due = item.due, due.day == today, let minute = due.minute, inScope(item, scope) else { continue }
            let at = due.day.date(atMinute: minute, calendar: calendar)
            if at > now && at < midnight { dates.insert(at) }
        }
        if let freshAt {
            let stale = freshAt.addingTimeInterval(Self.staleAfter)
            if stale > now && stale < midnight { dates.insert(stale) }
        }

        let entries = dates.sorted().map { date in
            WidgetEntry(
                date: date,
                category: category,
                content: .agenda(agenda(items: items, scope: scope, categories: byID, at: date)),
                staleLabel: staleLabel(freshAt: freshAt, at: date)
            )
        }
        return WidgetTimeline(entries: entries, refreshAt: midnight)
    }

    /// The store couldn't be opened: say so and try again soon.
    public func unavailable(now: Date) -> WidgetTimeline {
        let entry = WidgetEntry(date: now, category: nil, content: .storeUnavailable, staleLabel: nil)
        return WidgetTimeline(entries: [entry], refreshAt: now.addingTimeInterval(Self.retryAfter))
    }

    // MARK: Helpers

    private func inScope(_ item: ItemSnapshot, _ scope: CategoryScope) -> Bool {
        switch scope {
        case .all: true
        case .category(let id): item.categoryID == id
        }
    }

    private func agenda(items: [ItemSnapshot], scope: CategoryScope, categories: [UUID: CategorySnapshot], at date: Date) -> WidgetAgenda {
        let agenda = AgendaBuilder.build(items: items, scope: scope, now: date, calendar: calendar)
        let today = LocalDay(date, calendar: calendar)

        func row(_ item: ItemSnapshot, overdue: Bool) -> WidgetRow {
            var detail: String?
            var isLate = overdue
            if let due = item.due {
                if overdue {
                    detail = labels.dayTitle(due.day, today: today)
                } else if let minute = due.minute {
                    detail = labels.time(minute)
                    isLate = item.kind == .task && due.day == today && due.day.date(atMinute: minute, calendar: calendar) <= date
                }
            }
            return WidgetRow(
                id: item.id,
                title: item.title,
                kind: item.kind,
                category: item.categoryID.flatMap { categories[$0] },
                detail: detail,
                isLate: isLate
            )
        }

        var sections: [WidgetSection] = []
        if !agenda.overdue.isEmpty {
            sections.append(WidgetSection(id: "overdue", title: "Overdue", isOverdue: true, rows: agenda.overdue.map { row($0, overdue: true) }))
        }
        for day in agenda.days {
            sections.append(WidgetSection(
                id: day.day.isoString,
                title: labels.dayTitle(day.day, today: today),
                isOverdue: false,
                rows: day.items.map { row($0, overdue: false) }
            ))
        }
        let dueToday = agenda.days.first { $0.day == today }?.items ?? []
        return WidgetAgenda(
            sections: sections,
            todayCount: dueToday.count,
            dueTaskCount: agenda.overdue.count + dueToday.filter { $0.kind == .task }.count
        )
    }

    private func staleLabel(freshAt: Date?, at date: Date) -> String? {
        guard let freshAt, date.timeIntervalSince(freshAt) >= Self.staleAfter else { return nil }
        let freshDay = LocalDay(freshAt, calendar: calendar)
        let day = LocalDay(date, calendar: calendar)
        if freshDay == day {
            let clock = calendar.dateComponents([.hour, .minute], from: freshAt)
            return "Updated \(labels.time((clock.hour ?? 0) * 60 + (clock.minute ?? 0)))"
        }
        if freshDay == day.adding(days: -1, calendar: calendar) { return "Updated yesterday" }
        return "Updated \(labels.dayTitle(freshDay, today: day))"
    }
}
