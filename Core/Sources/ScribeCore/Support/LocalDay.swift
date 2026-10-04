import Foundation

/// A calendar day with no time zone attached ("floating"). 2026-10-12 stays
/// 2026-10-12 whether the device is in Israel, Thailand or Bulgaria.
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
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
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(parts.year!, parts.month!, parts.day!)
    }

    /// Returns nil for impossible dates such as 31/02.
    public static func validated(year: Int, month: Int, day: Int, calendar: Calendar) -> LocalDay? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let candidate = LocalDay(year, month, day)
        let roundTrip = LocalDay(candidate.date(atMinute: 12 * 60, calendar: calendar), calendar: calendar)
        return roundTrip == candidate ? candidate : nil
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year, month, day)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public func date(atMinute minute: Int = 0, calendar: Calendar) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: minute / 60, minute: minute % 60)
        return calendar.date(from: parts)!
    }

    /// Day arithmetic anchored at noon so DST transitions never shift the day.
    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        let noon = date(atMinute: 12 * 60, calendar: calendar)
        return LocalDay(calendar.date(byAdding: .day, value: days, to: noon)!, calendar: calendar)
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday, …)`.
    public func weekday(calendar: Calendar) -> Int {
        calendar.component(.weekday, from: date(atMinute: 12 * 60, calendar: calendar))
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
