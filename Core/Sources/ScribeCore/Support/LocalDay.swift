import Foundation

/// A calendar day with no time zone attached ("floating"). 2026-10-12 stays
/// 2026-10-12 whether the device is in Israel, Thailand or Bulgaria.
///
/// Always Gregorian: a calendar passed in only contributes its time zone, so a
/// device set to the Hebrew, Buddhist or Japanese calendar still stores and
/// syncs Gregorian "yyyy-MM-dd" days.
public struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        precondition((1...12).contains(month) && (1...31).contains(day), "invalid LocalDay \(year)-\(month)-\(day)")
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let parts = Self.gregorian(matching: calendar).dateComponents([.year, .month, .day], from: date)
        self.init(parts.year!, parts.month!, parts.day!)
    }

    /// Returns nil for impossible dates such as 31/02.
    public static func validated(year: Int, month: Int, day: Int, calendar: Calendar) -> LocalDay? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let candidate = LocalDay(year, month, day)
        let roundTrip = LocalDay(candidate.date(atMinute: 12 * 60, calendar: calendar), calendar: calendar)
        return roundTrip == candidate ? candidate : nil
    }

    /// Parses exactly "yyyy-MM-dd" (ASCII digits only) and rejects impossible dates.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let valid = Self.validated(year: year, month: month, day: day, calendar: Self.referenceCalendar) else { return nil }
        self = valid
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public func date(atMinute minute: Int = 0, calendar: Calendar) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: minute / 60, minute: minute % 60)
        return Self.gregorian(matching: calendar).date(from: parts)!
    }

    /// Day arithmetic anchored at noon so DST transitions never shift the day.
    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        let gregorian = Self.gregorian(matching: calendar)
        let noon = date(atMinute: 12 * 60, calendar: gregorian)
        return LocalDay(gregorian.date(byAdding: .day, value: days, to: noon)!, calendar: gregorian)
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday, …)`.
    public func weekday(calendar: Calendar) -> Int {
        let gregorian = Self.gregorian(matching: calendar)
        return gregorian.component(.weekday, from: date(atMinute: 12 * 60, calendar: gregorian))
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Validates "yyyy-MM-dd" strings, which carry no time zone.
    private static let referenceCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The Gregorian calendar in `calendar`'s time zone.
    private static func gregorian(matching calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}
