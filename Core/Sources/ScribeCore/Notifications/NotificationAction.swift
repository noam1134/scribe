import Foundation

/// The buttons on an item's notification (spec §11). They change the item
/// itself, so the change syncs like any other edit.
public enum NotificationAction: String, CaseIterable, Sendable {
    case done = "scribe.action.done"
    case inAnHour = "scribe.action.inAnHour"
    case tomorrow = "scribe.action.tomorrow"

    /// Button title.
    public var title: String {
        switch self {
        case .done: "Done"
        case .inAnHour: "+1 Hour"
        case .tomorrow: "Tomorrow"
        }
    }

    /// Applies the action. An item deleted since the alert fired is ignored.
    @MainActor
    public func perform(itemID: UUID, store: any ItemStore, now: Date, calendar: Calendar) throws {
        guard store.item(itemID) != nil else { return }
        switch self {
        case .done:
            try store.setDone(itemID, true)
        case .inAnHour:
            let due = Self.dueInAnHour(from: now, calendar: calendar)
            try store.updateItem(itemID) { $0.due = due }
        case .tomorrow:
            let today = LocalDay(now, calendar: calendar)
            try store.updateItem(itemID) { $0.due = Self.dueTomorrow(after: $0.due, today: today, calendar: calendar) }
        }
    }

    /// Now + 1 hour on the local clock, rounded up to the next 5 minutes
    /// (any seconds round up). May land on the next day.
    public static func dueInAnHour(from now: Date, calendar: Calendar) -> DueDate {
        let later = now.addingTimeInterval(60 * 60)
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: later)
        var minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if (parts.second ?? 0) > 0 || (parts.nanosecond ?? 0) > 0 { minute += 1 }
        minute = (minute + 4) / 5 * 5
        var day = LocalDay(later, calendar: calendar)
        if minute >= 24 * 60 {
            day = day.adding(days: 1, calendar: calendar)
            minute -= 24 * 60
        }
        return DueDate(day: day, minute: minute)
    }

    /// The day after the later of the due day and today, same time (or none).
    /// Normally the alert fired today, so this is simply tomorrow.
    public static func dueTomorrow(after due: DueDate?, today: LocalDay, calendar: Calendar) -> DueDate {
        let from = max(due?.day ?? today, today)
        return DueDate(day: from.adding(days: 1, calendar: calendar), minute: due?.minute)
    }
}
