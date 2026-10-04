import Foundation

/// Date phrases. Input is already lowercased.
/// Numeric dates are day/month (Israeli order).
enum DatePhrases {
    static func parse(_ phrase: String, today: LocalDay, calendar: Calendar) -> LocalDay? {
        if let offset = dayOffsets[phrase] { return today.adding(days: offset, calendar: calendar) }
        if let weekday = weekday(in: phrase) { return nextOccurrence(of: weekday, after: today, calendar: calendar) }
        if nextWeekPhrases.contains(phrase) { return nextOccurrence(of: calendar.firstWeekday, after: today, calendar: calendar) }
        if let days = relativeDays(phrase) { return today.adding(days: days, calendar: calendar) }
        if let day = numeric(phrase, today: today, calendar: calendar) { return day }
        if let day = monthName(phrase, today: today, calendar: calendar) { return day }
        return nil
    }

    static let dayOffsets: [String: Int] = [
        "today": 0, "tomorrow": 1, "tmr": 1, "tmrw": 1,
    ]

    /// 1 = Sunday … 7 = Saturday.
    static let englishWeekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    static let nextWeekPhrases: Set<String> = ["next week"]

    static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    static func weekday(in phrase: String) -> Int? {
        let english = phrase.hasPrefix("next ") ? String(phrase.dropFirst(5)) : phrase
        return englishWeekdays[english]
    }

    /// Strictly after today: "fri" typed on a Friday means next week's Friday.
    static func nextOccurrence(of weekday: Int, after today: LocalDay, calendar: Calendar) -> LocalDay {
        var delta = (weekday - today.weekday(calendar: calendar) + 7) % 7
        if delta == 0 { delta = 7 }
        return today.adding(days: delta, calendar: calendar)
    }

    static func relativeDays(_ phrase: String) -> Int? {
        let words = phrase.split(separator: " ").map(String.init)
        guard words.count == 3, let count = Int(words[1]), (1...365).contains(count) else { return nil }
        switch (words[0], words[2]) {
        case ("in", "day"), ("in", "days"): return count
        case ("in", "week"), ("in", "weeks"): return count * 7
        default: return nil
        }
    }

    /// "12/10", "12.10", "12/10/26", "12/10/2026" — day first.
    static func numeric(_ phrase: String, today: LocalDay, calendar: Calendar) -> LocalDay? {
        let parts = phrase.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "." }).map(String.init)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts[0].count <= 2, parts[1].count <= 2,
              let day = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        guard parts.count == 3 else { return upcoming(month: month, day: day, today: today, calendar: calendar) }
        guard parts[2].count == 2 || parts[2].count == 4, var year = Int(parts[2]) else { return nil }
        if parts[2].count == 2 { year += 2000 }
        return LocalDay.validated(year: year, month: month, day: day, calendar: calendar)
    }

    /// "oct 12", "12 oct", "october 12".
    static func monthName(_ phrase: String, today: LocalDay, calendar: Calendar) -> LocalDay? {
        let words = phrase.split(separator: " ").map(String.init)
        guard words.count == 2 else { return nil }
        let (monthWord, dayWord) = monthNames[words[0]] != nil ? (words[0], words[1]) : (words[1], words[0])
        guard let month = monthNames[monthWord], let day = Int(dayWord) else { return nil }
        return upcoming(month: month, day: day, today: today, calendar: calendar)
    }

    /// A day/month without a year: this year, or next year if already past.
    static func upcoming(month: Int, day: Int, today: LocalDay, calendar: Calendar) -> LocalDay? {
        if let thisYear = LocalDay.validated(year: today.year, month: month, day: day, calendar: calendar), thisYear >= today {
            return thisYear
        }
        return LocalDay.validated(year: today.year + 1, month: month, day: day, calendar: calendar)
    }
}
