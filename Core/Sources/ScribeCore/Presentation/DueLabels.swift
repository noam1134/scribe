import Foundation

/// Short human labels for days and due dates, shared by the app and widgets.
public struct DueLabels: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "Today", "Tomorrow", "Yesterday", or e.g. "Fri, 9 Oct".
    public func dayTitle(_ day: LocalDay, today: LocalDay) -> String {
        switch day {
        case today: return "Today"
        case today.adding(days: 1, calendar: calendar): return "Tomorrow"
        case today.adding(days: -1, calendar: calendar): return "Yesterday"
        default:
            var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
            if day.year != today.year { style = style.year() }
            return day.date(atMinute: 12 * 60, calendar: calendar).formatted(style)
        }
    }

    /// "09:30" — 24-hour clock.
    public func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// "Today", "Tomorrow · 09:30", "Fri, 9 Oct · 18:00".
    public func due(_ due: DueDate, today: LocalDay) -> String {
        let day = dayTitle(due.day, today: today)
        guard let minute = due.minute else { return day }
        return "\(day) · \(time(minute))"
    }
}
