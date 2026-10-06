import Foundation

/// What the app publishes to the Claude mailbox (`mailbox/` Worker): its
/// categories and what's coming up, so Claude can file items and answer
/// "what do I have this week?". Titles only — no notes.
public struct MailboxSnapshot: Codable, Equatable, Sendable {
    public struct Category: Codable, Equatable, Sendable {
        public var name: String
        public var emoji: String

        public init(name: String, emoji: String) {
            self.name = name
            self.emoji = emoji
        }
    }

    public struct Upcoming: Codable, Equatable, Sendable {
        public var title: String
        public var category: String
        public var kind: ItemKind
        /// "yyyy-MM-dd".
        public var dueDate: String
        /// "HH:mm", 24-hour.
        public var dueTime: String?

        public init(title: String, category: String, kind: ItemKind, dueDate: String, dueTime: String? = nil) {
            self.title = title
            self.category = category
            self.kind = kind
            self.dueDate = dueDate
            self.dueTime = dueTime
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var updatedAt: Date
    /// The device's time zone: the Worker works out "today" and "overdue" in it.
    public var timeZone: String
    public var categories: [Category]
    public var upcoming: [Upcoming]

    public init(version: Int = currentVersion, updatedAt: Date, timeZone: String, categories: [Category], upcoming: [Upcoming]) {
        self.version = version
        self.updatedAt = updatedAt
        self.timeZone = timeZone
        self.categories = categories
        self.upcoming = upcoming
    }

    /// Same categories and items, whenever it was built.
    public func hasSameContent(as other: MailboxSnapshot) -> Bool {
        timeZone == other.timeZone && categories == other.categories && upcoming == other.upcoming
    }
}

/// An item Claude queued in the mailbox.
public struct MailboxItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// A category name as Claude saw it in the snapshot, or a new one.
    public var category: String
    /// Claude proposed a new category (the user asked for it).
    public var createCategory: Bool
    public var kind: ItemKind
    public var dueDate: String?
    public var dueTime: String?
    public var notes: String?

    public init(
        id: String,
        title: String,
        category: String,
        createCategory: Bool = false,
        kind: ItemKind = .task,
        dueDate: String? = nil,
        dueTime: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.createCategory = createCategory
        self.kind = kind
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, createCategory, kind, dueDate, dueTime, notes
    }

    /// Lenient about everything but the id and title: an item the app can't
    /// fully read still lands somewhere instead of blocking the inbox.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        createCategory = try container.decodeIfPresent(Bool.self, forKey: .createCategory) ?? false
        kind = (try? container.decodeIfPresent(ItemKind.self, forKey: .kind)) ?? .task
        dueDate = try? container.decodeIfPresent(String.self, forKey: .dueDate)
        dueTime = try? container.decodeIfPresent(String.self, forKey: .dueTime)
        notes = try? container.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// `GET inbox`.
public struct MailboxInbox: Codable, Equatable, Sendable {
    public var items: [MailboxItem]

    public init(items: [MailboxItem]) {
        self.items = items
    }
}

/// `POST inbox/ack`.
public struct MailboxAck: Codable, Equatable, Sendable {
    public var ids: [String]

    public init(ids: [String]) {
        self.ids = ids
    }
}

extension MailboxSnapshot {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
