/// Time phrases in English and Hebrew. Input is already lowercased.
enum TimePhrases {
    static func parse(_ phrase: String) -> TimeValue? {
        if let named = namedTimes[phrase] { return named }
        // With a prefix a bare hour is allowed ("at 9", "ב-9"); without one it
        // is not, so a lone "9" in a title is never read as a time.
        // Longest prefix first: "בשעה " before "ב-" before "ב".
        for prefix in ["at ", "בשעה ", "ב-", "ב"] where phrase.hasPrefix(prefix) {
            let rest = String(phrase.dropFirst(prefix.count))
            if let named = namedTimes[rest] { return named }
            return clock(rest, allowsBareHour: true)
        }
        return clock(phrase, allowsBareHour: false)
    }

    static let namedTimes: [String: TimeValue] = [
        "noon": TimeValue(minute: 12 * 60, pinsToday: false, isUnambiguous: true),
        "בצהריים": TimeValue(minute: 12 * 60, pinsToday: false, isUnambiguous: true),
        "tonight": TimeValue(minute: 20 * 60, pinsToday: true),
        "הערב": TimeValue(minute: 20 * 60, pinsToday: true),
    ]

    /// "9am", "9:30pm", "9 am", "14:30", and (if allowed) "9" as 24-hour.
    /// The only space allowed is one before am/pm, so "1 2" never merges into 12.
    static func clock(_ text: String, allowsBareHour: Bool) -> TimeValue? {
        var body = Substring(text)
        var meridiem: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            meridiem = String(body.suffix(2))
            body = body.dropLast(2)
            if body.hasSuffix(" ") { body = body.dropLast() }
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
        return TimeValue(minute: hour * 60 + minute, pinsToday: false, isUnambiguous: meridiem != nil)
    }
}
