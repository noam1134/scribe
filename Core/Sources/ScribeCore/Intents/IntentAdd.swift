import Foundation

/// The logic behind adding by Siri or Shortcuts (spec §8): the same parser
/// as the composer, and — like the composer — every item ends in a real
/// category (spec §19). Nothing here talks to Siri; the App Intent asks the
/// questions this decides on.
public enum IntentAdd {
    public enum Resolution: Equatable, Sendable {
        /// Ready to save; `categoryID` is set.
        case ready(ItemDraft)
        /// Everything but the category: ask which one.
        case needsCategory(ItemDraft)
        /// There is no category to file into yet.
        case noCategories
        /// Nothing left to call the item: ask for the text again.
        case emptyTitle
    }

    /// The category comes from, in order: the intent's Category parameter
    /// (when it still exists), a `#tag` in the text, a mention ("… for
    /// work"), or the only category there is. Otherwise the user is asked
    /// (the app may first ask the on-device model). An unknown `#tag` stays
    /// in the title, as in the composer, and so does a mention the
    /// parameter overrides. Request phrases ("remind me to") leave the title.
    public static func resolve(_ text: String, categoryID: UUID?, categories: [CategorySnapshot], now: Date, calendar: Calendar) -> Resolution {
        let parser = QuickAddParser(calendar: calendar)
        let parameter = categoryID.flatMap { id in categories.contains { $0.id == id } ? id : nil }
        var parsed = parser.nonInteractiveParse(text, categories: categories, now: now)
        if let parameter, let mentioned = parsed.mentionedCategoryID, mentioned != parameter {
            parsed = parser.nonInteractiveParse(text, categories: categories, now: now, disabled: [.mention])
        }
        guard var draft = parsed.itemDraft else { return .emptyTitle }
        guard !categories.isEmpty else { return .noCategories }
        if let parameter {
            draft.categoryID = parameter
        } else if draft.categoryID == nil, categories.count == 1 {
            draft.categoryID = categories[0].id
        }
        return draft.categoryID == nil ? .needsCategory(draft) : .ready(draft)
    }

    /// Categories whose name matches what Siri heard: exact matches, then
    /// prefixes, then names containing it; each group in the user's order.
    /// An empty query lists every category.
    public static func categories(matching query: String, in categories: [CategorySnapshot]) -> [CategorySnapshot] {
        let ordered = categories.sorted { $0.sortIndex < $1.sortIndex }
        let key = TextNormalizer.key(query)
        guard !key.isEmpty else { return ordered }
        let keyed = ordered.map { (category: $0, key: TextNormalizer.key($0.name)) }
        let exact = keyed.filter { $0.key == key }
        let prefix = keyed.filter { $0.key != key && $0.key.hasPrefix(key) }
        let contains = keyed.filter { !$0.key.hasPrefix(key) && $0.key.contains(key) }
        return (exact + prefix + contains).map(\.category)
    }

    /// What Siri says after saving: "Added ‘Book flights’ to Thailand, Friday."
    public static func reply(title: String, categoryName: String, due: DueDate?, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let due else { return "Added ‘\(title)’ to \(categoryName)." }
        var when = spokenDay(due.day, today: LocalDay(now, calendar: calendar), calendar: calendar, locale: locale)
        if let minute = due.minute {
            when += " at " + DueLabels(calendar: calendar, locale: locale).time(minute)
        }
        return "Added ‘\(title)’ to \(categoryName), \(when)."
    }

    /// "today", "tomorrow", "Friday" within the coming week, else the date.
    private static func spokenDay(_ day: LocalDay, today: LocalDay, calendar: Calendar, locale: Locale) -> String {
        switch day {
        case today: return "today"
        case today.adding(days: 1, calendar: calendar): return "tomorrow"
        case today.adding(days: -1, calendar: calendar): return "yesterday"
        default:
            let date = day.date(atMinute: 12 * 60, calendar: calendar)
            let base = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            if day > today && day < today.adding(days: 7, calendar: calendar) {
                return date.formatted(base.weekday(.wide))
            }
            var style = base.day().month(.wide)
            if day.year != today.year { style = style.year() }
            return date.formatted(style)
        }
    }
}
