import Foundation

/// Turns quick-add text like "book flights fri #thailand" into a draft.
///
/// Only TRAILING tokens are recognized: the parser walks words from the end
/// and stops at the first word it doesn't understand. "ארוחת שבת עם המשפחה"
/// therefore keeps "שבת" in the title. Each token kind is used at most once,
/// except that "tonight" / "הערב" may pair with one explicit time, so a draft
/// can carry two `.time` tokens.
///
/// Plain language too: a trailing category mention ("… for work", see
/// `CategoryMention`) is a token, and leading request phrases ("remind me
/// to …", see `RequestPhrases`) leave the title.
public struct QuickAddParser: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// Longest phrase the recognizers understand ("in 3 days", "בעוד 3 ימים").
    static let maxPhraseWords = 3
    static let memoMarkers: Set<String> = ["!memo", "!note", "!פתק"]

    enum Recognition {
        case category(CategoryMatch)
        case kind(ItemKind)
        case date(LocalDay)
        case time(TimeValue)
        case mention(UUID)

        var tokenKind: TokenKind {
            switch self {
            case .category: .category
            case .kind: .kind
            case .date: .date
            case .time: .time
            case .mention: .mention
            }
        }
    }

    /// - Parameter disabled: token kinds the user dismissed (tapped the chip).
    ///   Their text stays in the title instead of being interpreted.
    public func parse(_ text: String, categories: [CategorySnapshot], now: Date, disabled: Set<TokenKind> = []) -> ParsedDraft {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let today = LocalDay(now, calendar: calendar)

        var end = words.count
        var used = Set<TokenKind>()
        var foundTimes: [TimeValue] = []
        var found: [(start: Int, text: String, recognition: Recognition)] = []
        scanning: while end > 0 {
            for length in stride(from: min(Self.maxPhraseWords, end), through: 1, by: -1) {
                let phrase = words[(end - length)..<end].joined(separator: " ")
                guard let recognition = recognize(phrase, today: today, categories: categories),
                      Self.canUse(recognition, used: used, foundTimes: foundTimes) else { continue }
                used.insert(recognition.tokenKind)
                if case .time(let value) = recognition { foundTimes.append(value) }
                found.append((end - length, phrase, recognition))
                end -= length
                continue scanning
            }
            if !used.contains(.mention), let mention = mention(endingAt: end, in: words, categories: categories) {
                used.insert(.mention)
                let start = end - mention.length
                found.append((start, words[start..<end].joined(separator: " "), .mention(mention.categoryID)))
                end = start
                continue scanning
            }
            break
        }
        found.sort { $0.start < $1.start }

        // A `#tag` beats a mention of another category: "fix sink in Home
        // #work" keeps "in Home" in the title.
        let tag = found.lazy.compactMap { token -> CategoryMatch? in
            if case .category(let match) = token.recognition { return match }
            return nil
        }.first
        var draft = ParsedDraft(title: "", kind: .task, category: .none, due: nil, tokens: [])
        var titleWords = Array(words[0..<end])
        var date: LocalDay?
        var times: [TimeValue] = []
        for token in found {
            var isOff = disabled.contains(token.recognition.tokenKind)
            if case .mention(let id) = token.recognition, let tag, tag != .matched(id) { isOff = true }
            guard !isOff else {
                titleWords.append(token.text)
                continue
            }
            draft.tokens.append(RecognizedToken(kind: token.recognition.tokenKind, text: token.text))
            switch token.recognition {
            case .category(let match): draft.category = match
            case .kind(let kind): draft.kind = kind
            case .date(let day): date = day
            case .time(let value): times.append(value)
            case .mention(let id): draft.mentionedCategoryID = id
            }
        }
        let title = titleWords.joined(separator: " ")
        draft.title = RequestPhrases.cleaned(title) ?? title
        // "tomorrow for family": a mention never takes the last of the title.
        if draft.title.isEmpty, draft.mentionedCategoryID != nil {
            return parse(text, categories: categories, now: now, disabled: disabled.union([.mention]))
        }
        draft.due = resolveDue(date: date, time: Self.combine(times), today: today, now: now)
        return draft
    }

    /// For paths with no screen to confirm on (Siri, Shortcuts): an unknown
    /// `#tag` is not interpreted — the item goes to the Inbox with the tag
    /// kept in its title.
    public func nonInteractiveDraft(_ text: String, categories: [CategorySnapshot], now: Date) -> ItemDraft? {
        nonInteractiveParse(text, categories: categories, now: now).itemDraft
    }

    func nonInteractiveParse(_ text: String, categories: [CategorySnapshot], now: Date, disabled: Set<TokenKind> = []) -> ParsedDraft {
        let parsed = parse(text, categories: categories, now: now, disabled: disabled)
        guard case .unknown = parsed.category else { return parsed }
        return parse(text, categories: categories, now: now, disabled: disabled.union([.category]))
    }

    // MARK: Recognition

    /// A mention that leaves something of the title once its request
    /// phrases go: "remind me for work" is not filed as "".
    private func mention(endingAt end: Int, in words: [String], categories: [CategorySnapshot]) -> CategoryMention.Match? {
        guard let match = CategoryMention.trailing(in: words[0..<end], categories: categories) else { return nil }
        let rest = words[0..<(end - match.length)].joined(separator: " ")
        guard !RequestPhrases.isEmptyRequest(rest) else { return nil }
        return match
    }

    private func recognize(_ rawPhrase: String, today: LocalDay, categories: [CategorySnapshot]) -> Recognition? {
        let phrase = Self.droppingTrailingPunctuation(rawPhrase)
        let lower = phrase.lowercased()
        if let match = Self.categoryTag(phrase, categories: categories) { return .category(match) }
        if Self.memoMarkers.contains(lower) { return .kind(.memo) }
        if let day = DatePhrases.parse(lower, today: today, calendar: calendar) { return .date(day) }
        if let value = TimePhrases.parse(lower) { return .time(value) }
        return nil
    }

    private static func categoryTag(_ phrase: String, categories: [CategorySnapshot]) -> CategoryMatch? {
        guard phrase.hasPrefix("#"), phrase.count > 1, !phrase.contains(" ") else { return nil }
        let name = String(phrase.dropFirst())
        let key = TextNormalizer.key(name)
        let ordered = categories.sorted { $0.sortIndex < $1.sortIndex }
        if let exact = ordered.first(where: { TextNormalizer.key($0.name) == key }) { return .matched(exact.id) }
        if let prefix = ordered.first(where: { TextNormalizer.key($0.name).hasPrefix(key) }) { return .matched(prefix.id) }
        return .unknown(name)
    }

    /// "tomorrow." and "fri," still count; "!memo" keeps its leading "!".
    private static func droppingTrailingPunctuation(_ phrase: String) -> String {
        var result = phrase
        while result.count > 1, let last = result.last, ".,;:?!".contains(last) {
            result.removeLast()
        }
        return result
    }

    // MARK: Due date resolution

    /// Each kind is used once, except that "tonight" / "הערב" may pair with
    /// one explicit time ("tonight at 9", "הערב ב-9").
    private static func canUse(_ recognition: Recognition, used: Set<TokenKind>, foundTimes: [TimeValue]) -> Bool {
        guard case .time(let value) = recognition else { return !used.contains(recognition.tokenKind) }
        switch foundTimes.count {
        case 0: return true
        case 1: return foundTimes[0].pinsToday != value.pinsToday
        default: return false
        }
    }

    /// "tonight" plus an explicit time: today at that time, and an hour of
    /// 1–11 without am/pm reads as evening ("tonight at 9" → 21:00).
    private static func combine(_ times: [TimeValue]) -> TimeValue? {
        guard times.count == 2, let explicit = times.first(where: { !$0.pinsToday }) else { return times.first }
        let isMorningHour = (60..<(12 * 60)).contains(explicit.minute)
        let minute = !explicit.isUnambiguous && isMorningHour ? explicit.minute + 12 * 60 : explicit.minute
        return TimeValue(minute: minute, pinsToday: true, isUnambiguous: true)
    }

    private func resolveDue(date: LocalDay?, time: TimeValue?, today: LocalDay, now: Date) -> DueDate? {
        switch (date, time) {
        case let (day?, time):
            return DueDate(day: day, minute: time?.minute)
        case let (nil, time?):
            if time.pinsToday { return DueDate(day: today, minute: time.minute) }
            let clock = calendar.dateComponents([.hour, .minute], from: now)
            let nowMinute = clock.hour! * 60 + clock.minute!
            let day = time.minute > nowMinute ? today : today.adding(days: 1, calendar: calendar)
            return DueDate(day: day, minute: time.minute)
        case (nil, nil):
            return nil
        }
    }
}
