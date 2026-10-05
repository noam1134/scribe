import Foundation

/// The quick date choices in a row's menu and the editor's date chip.
/// "Next Week" means what typing "next week" means: the first day of next
/// week on this device's calendar.
public enum DatePreset: CaseIterable, Sendable {
    case today, tomorrow, nextWeek

    public var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        }
    }

    public func day(today: LocalDay, calendar: Calendar) -> LocalDay {
        switch self {
        case .today: today
        case .tomorrow: today.adding(days: 1, calendar: calendar)
        case .nextWeek: DatePhrases.nextOccurrence(of: calendar.firstWeekday, after: today, calendar: calendar)
        }
    }

    /// The new due date; keeps the time the item already had.
    public func applied(to due: DueDate?, today: LocalDay, calendar: Calendar) -> DueDate {
        DueDate(day: day(today: today, calendar: calendar), minute: due?.minute)
    }
}
