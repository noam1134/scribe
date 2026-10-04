/// Time phrases. Input is already lowercased.
enum TimePhrases {
    static func parse(_ phrase: String) -> TimeValue? {
        switch phrase {
        case "noon": return TimeValue(minute: 12 * 60, pinsToday: false)
        case "tonight": return TimeValue(minute: 20 * 60, pinsToday: true)
        default: break
        }
        // With a prefix a bare hour is allowed ("at 9"); without one it is
        // not, so a lone "9" in a title is never read as a time.
        for prefix in ["at "] where phrase.hasPrefix(prefix) {
            return clock(String(phrase.dropFirst(prefix.count)), allowsBareHour: true).map { TimeValue(minute: $0, pinsToday: false) }
        }
        return clock(phrase, allowsBareHour: false).map { TimeValue(minute: $0, pinsToday: false) }
    }

    /// "9am", "9:30pm", "9 am", "14:30", and (if allowed) "9" as 24-hour.
    static func clock(_ text: String, allowsBareHour: Bool) -> Int? {
        var body = text.replacingOccurrences(of: " ", with: "")
        var meridiem: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            meridiem = String(body.suffix(2))
            body.removeLast(2)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              var hour = Int(parts[0]) else { return nil }
        if parts.count == 2 && parts[1].count != 2 { return nil }
        let minute = parts.count == 2 ? Int(parts[1])! : 0
        guard (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        } else {
            guard parts.count == 2 || allowsBareHour, (0...23).contains(hour) else { return nil }
        }
        return hour * 60 + minute
    }
}
