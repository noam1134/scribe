/// When an item is due: a floating day plus an optional floating time
/// (minutes after local midnight).
public struct DueDate: Hashable, Comparable, Codable, Sendable {
    public var day: LocalDay
    public var minute: Int?

    public init(day: LocalDay, minute: Int? = nil) {
        precondition(minute.map { (0..<1440).contains($0) } ?? true, "minute must be in 0..<1440")
        self.day = day
        self.minute = minute
    }

    public var hasTime: Bool { minute != nil }

    /// Earlier day first; on the same day, untimed before timed, then by time.
    public static func < (lhs: DueDate, rhs: DueDate) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        switch (lhs.minute, rhs.minute) {
        case let (l?, r?): return l < r
        case (nil, _?): return true
        default: return false
        }
    }
}
