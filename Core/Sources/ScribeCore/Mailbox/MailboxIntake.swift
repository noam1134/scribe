import Foundation

/// The mailbox ids this device already turned into items, so an item that
/// comes back (its acknowledgement was lost) isn't added twice. Per device,
/// in the App Group's defaults; the newest `limit` ids are kept.
public struct MailboxLedger: Codable, Equatable, Sendable {
    public static let limit = 500
    public static let defaultsKey = "mailbox.collectedIDs"

    public private(set) var ids: [String] = []

    public init() {}

    public func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    public mutating func record(_ id: String) {
        guard !contains(id) else { return }
        ids.append(id)
        if ids.count > Self.limit { ids.removeFirst(ids.count - Self.limit) }
    }

    public init(from defaults: UserDefaults, key: String = defaultsKey) {
        self.init()
        ids = Array((defaults.stringArray(forKey: key) ?? []).suffix(Self.limit))
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        defaults.set(ids, forKey: key)
    }
}

/// Turns the items Claude queued into Scribe items (spec §19: every item in
/// a real category).
public enum MailboxIntake {
    public struct Outcome: Equatable, Sendable {
        /// New items, in the mailbox's order.
        public var added: [UUID] = []
        /// Categories made for them.
        public var createdCategories: [UUID] = []
        /// Mailbox ids to acknowledge: added now, added before, or unusable.
        public var acknowledged: [String] = []
        /// Items the store refused to save; they stay in the mailbox for the next try.
        public var failed: [String] = []
    }

    /// The category is the one whose name matches, ignoring case, accents,
    /// width and spaces (the store's duplicate-name rule). An unknown name
    /// gets a new category, whether or not Claude flagged it as new: Claude
    /// was told to ask the user, and Scribe never files into the Inbox.
    /// An item without a title can never be added; it's acknowledged and
    /// dropped. Items the ledger has seen are acknowledged again, not added.
    @MainActor
    public static func collect(_ items: [MailboxItem], into store: any ItemStore, ledger: inout MailboxLedger) -> Outcome {
        var outcome = Outcome()
        for item in items {
            if ledger.contains(item.id) {
                outcome.acknowledged.append(item.id)
                continue
            }
            guard let draft = draft(for: item, categoryID: nil) else {
                outcome.acknowledged.append(item.id)
                continue
            }
            do {
                let category = try categoryID(named: item.category, in: store, created: &outcome.createdCategories)
                var filed = draft
                filed.categoryID = category
                outcome.added.append(try store.addItem(filed))
                ledger.record(item.id)
                outcome.acknowledged.append(item.id)
            } catch {
                outcome.failed.append(item.id)
            }
        }
        return outcome
    }

    /// The item without its category: title and notes trimmed, the due
    /// date if it's a real day (a bad time is dropped, the day kept). Nil
    /// for an empty title.
    public static func draft(for item: MailboxItem, categoryID: UUID?) -> ItemDraft? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let due = item.dueDate.flatMap(LocalDay.init(isoString:)).map { DueDate(day: $0, minute: item.dueTime.flatMap(minute(of:))) }
        return ItemDraft(
            title: title,
            body: item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            kind: item.kind,
            categoryID: categoryID,
            due: due
        )
    }

    /// "09:30" → 570; nil unless exactly HH:mm on a 24-hour clock.
    static func minute(of time: String) -> Int? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// An empty name files the item in the Inbox (the Worker never sends one).
    @MainActor
    private static func categoryID(named raw: String, in store: any ItemStore, created: inout [UUID]) throws -> UUID? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let key = TextNormalizer.key(name)
        let categories = store.categories
        if let match = categories.first(where: { TextNormalizer.key($0.name) == key }) {
            return match.id
        }
        let color = CategoryPalette.suggestedColorName(avoiding: categories.map(\.colorName))
        let id = try store.addCategory(CategoryDraft(name: name, colorName: color))
        created.append(id)
        return id
    }
}
