import Foundation

public enum CategoryScope: Hashable, Sendable {
    case all
    case category(UUID)
}

public struct AgendaDay: Equatable, Sendable {
    public let day: LocalDay
    public let items: [ItemSnapshot]
}

/// What's coming up: overdue tasks, then today and the next 6 days.
/// Empty days are omitted.
public struct Agenda: Equatable, Sendable {
    public let overdue: [ItemSnapshot]
    public let days: [AgendaDay]

    public var isEmpty: Bool { overdue.isEmpty && days.isEmpty }
}

public enum AgendaBuilder {
    /// Today plus the next 6 days.
    public static let dayCount = 7

    public static func build(items: [ItemSnapshot], scope: CategoryScope, now: Date, calendar: Calendar) -> Agenda {
        let today = LocalDay(now, calendar: calendar)
        let lastDay = today.adding(days: dayCount - 1, calendar: calendar)
        let scoped = items.filter { item in
            switch scope {
            case .all: return true
            case .category(let id): return item.categoryID == id
            }
        }

        let overdue = scoped
            .filter { item in
                guard item.kind == .task, !item.isDone, let due = item.due else { return false }
                return due.day < today
            }
            .sorted(by: ItemOrdering.byDue)

        var byDay: [LocalDay: [ItemSnapshot]] = [:]
        for item in scoped where !item.isDone {
            guard let due = item.due, due.day >= today, due.day <= lastDay else { continue }
            byDay[due.day, default: []].append(item)
        }
        let days = byDay.keys.sorted().map { day in
            AgendaDay(day: day, items: byDay[day, default: []].sorted(by: ItemOrdering.byDue))
        }
        return Agenda(overdue: overdue, days: days)
    }
}
