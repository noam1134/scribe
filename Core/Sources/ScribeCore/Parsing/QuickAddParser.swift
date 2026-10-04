import Foundation

/// Turns quick-add text like "book flights fri #thailand" into a draft.
///
/// Only TRAILING tokens are recognized: the parser walks words from the end
/// and stops at the first word it doesn't understand. "ארוחת שבת עם המשפחה"
/// therefore keeps "שבת" in the title. Each token kind is used at most once.
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

        var tokenKind: TokenKind {
            switch self {
            case .category: .category
            case .kind: .kind
            case .date: .date
            case .time: .time
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
        var found: [(start: Int, text: String, recognition: Recognition)] = []
        scanning: while end > 0 {
            for length in stride(from: min(Self.maxPhraseWords, end), through: 1, by: -1) {
                let phrase = words[(end - length)..<end].joined(separator: " ")
                guard let recognition = recognize(phrase, today: today, categories: categories),
                      !used.contains(recognition.tokenKind) else { continue }
                used.insert(recognition.tokenKind)
                found.append((end - length, phrase, recognition))
                end -= length
                continue scanning
            }
            break
        }
        found.sort { $0.start < $1.start }

        var draft = ParsedDraft(title: "", kind: .task, category: .none, due: nil, tokens: [])
        var titleWords = Array(words[0..<end])
        var date: LocalDay?
        var time: TimeValue?
        for token in found {
            guard !disabled.contains(token.recognition.tokenKind) else {
                titleWords.append(token.text)
                continue
            }
            draft.tokens.append(RecognizedToken(kind: token.recognition.tokenKind, text: token.text))
            switch token.recognition {
            case .category(let match): draft.category = match
            case .kind(let kind): draft.kind = kind
            case .date(let day): date = day
            case .time(let value): time = value
            }
        }
        draft.title = titleWords.joined(separator: " ")
        draft.due = resolveDue(date: date, time: time, today: today, now: now)
        return draft
    }

    /// For paths with no screen to confirm on (Siri, Shortcuts): an unknown
    /// `#tag` is not interpreted — the item goes to the Inbox with the tag
    /// kept in its title.
    public func nonInteractiveDraft(_ text: String, categories: [CategorySnapshot], now: Date) -> ItemDraft? {
        var parsed = parse(text, categories: categories, now: now)
        if case .unknown = parsed.category {
            parsed = parse(text, categories: categories, now: now, disabled: [.category])
        }
        return parsed.itemDraft
    }

    // MARK: Recognition

    private func recognize(_ rawPhrase: String, today: LocalDay, categories: [CategorySnapshot]) -> Recognition? {
        let phrase = Self.droppingTrailingPunctuation(rawPhrase)
        let lower = phrase.lowercased()
        if let match = Self.categoryTag(phrase, categories: categories) { return .category(match) }
        if Self.memoMarkers.contains(lower) { return .kind(.memo) }
        if let day = DatePhrases.parse(lower, today: today, calendar: calendar) { return .date(day) }
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
