import Foundation

/// Builds what the app publishes to the Claude mailbox from the store's data.
public enum MailboxSnapshotBuilder {
    /// Days ahead, today included: Claude may ask for up to a month.
    public static let dayCount = 30
    /// At most this many items in all…
    public static let itemLimit = 200
    /// …of which at most this many overdue ones, the most recent kept.
    public static let overdueLimit = 50
    /// The Worker's limits (UTF-16 code units, as JavaScript counts).
    static let titleLimit = 500
    static let nameLimit = 100
    static let emojiLimit = 32
    static let categoryLimit = 300

    /// `categories` in the user's order; `items` are the store's
    /// `datedOpenItems()` (open tasks and dated memos). Overdue tasks and
    /// everything due in the next `dayCount` days, by due date; memos never
    /// become overdue. Items in the Inbox are listed under "Inbox".
    public static func build(categories: [CategorySnapshot], items: [ItemSnapshot], now: Date, calendar: Calendar) -> MailboxSnapshot {
        let today = LocalDay(now, calendar: calendar)
        let lastDay = today.adding(days: dayCount - 1, calendar: calendar)
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let open = items.filter { !$0.isDone && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let dated = open.compactMap { item in item.due.map { (item, $0) } }.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.createdAt < rhs.0.createdAt
        }
        let overdue = dated.filter { $0.0.kind == .task && $0.1.day < today }.suffix(overdueLimit)
        let coming = dated.filter { $0.1.day >= today && $0.1.day <= lastDay }.prefix(itemLimit - overdue.count)

        let upcoming = (Array(overdue) + Array(coming)).map { item, due in
            MailboxSnapshot.Upcoming(
                title: clipped(item.title.trimmingCharacters(in: .whitespacesAndNewlines), to: titleLimit),
                category: clipped(item.categoryID.flatMap { names[$0] } ?? "Inbox", to: nameLimit),
                kind: item.kind,
                dueDate: due.day.isoString,
                dueTime: due.minute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
            )
        }
        let published = categories.compactMap { category -> MailboxSnapshot.Category? in
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return MailboxSnapshot.Category(name: clipped(name, to: nameLimit), emoji: clipped(category.emoji, to: emojiLimit))
        }
        return MailboxSnapshot(
            updatedAt: now,
            timeZone: ianaName(of: calendar.timeZone),
            categories: Array(published.prefix(categoryLimit)),
            upcoming: upcoming
        )
    }

    /// The Worker accepts IANA names only; a custom zone (rare) becomes UTC.
    static func ianaName(of timeZone: TimeZone) -> String {
        TimeZone.knownTimeZoneIdentifiers.contains(timeZone.identifier) ? timeZone.identifier : "UTC"
    }

    /// At most `limit` UTF-16 code units, cut between characters.
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var result = ""
        var count = 0
        for character in text {
            let size = character.utf16.count
            guard count + size <= limit else { break }
            result.append(character)
            count += size
        }
        return result
    }
}
