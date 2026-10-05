import Foundation

/// What the Mac menu bar panel lists: overdue tasks, then today's items.
public struct TodayAgenda: Equatable, Sendable {
    public let overdue: [ItemSnapshot]
    public let today: [ItemSnapshot]

    public init(_ agenda: Agenda, today day: LocalDay) {
        overdue = agenda.overdue
        today = agenda.days.first { $0.day == day }?.items ?? []
    }

    public var isEmpty: Bool { overdue.isEmpty && today.isEmpty }
}
