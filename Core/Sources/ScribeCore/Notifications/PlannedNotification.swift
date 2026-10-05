import Foundation

/// Which buttons a notification offers — maps 1:1 to a
/// `UNNotificationCategory` the app registers.
public enum NotificationCategory: String, CaseIterable, Sendable {
    case task = "scribe.item.task"
    case memo = "scribe.item.memo"
    case summary = "scribe.summary"

    /// Spec §11: Done (tasks only), +1 hour, Tomorrow; none on the summary.
    public var actions: [NotificationAction] {
        switch self {
        case .task: [.done, .inAnHour, .tomorrow]
        case .memo: [.inAnHour, .tomorrow]
        case .summary: []
        }
    }
}

/// One local notification the planner wants pending. The app turns it into
/// a `UNNotificationRequest` with a calendar trigger built from `trigger`.
public struct PlannedNotification: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The alert at a timed item's due time.
        case due(itemID: UUID)
        /// The morning summary of one day.
        case morningSummary(LocalDay)
    }

    /// Stable request identifier: `item.<uuid>` or `summary.<yyyy-MM-dd>`.
    /// Re-planning yields the same id, so adding it again replaces it.
    public let id: String
    public let kind: Kind
    public let category: NotificationCategory
    /// When it fires in the planning calendar's time zone (ordering, budget).
    public let fireDate: Date
    /// Floating wall-clock date and time in the device calendar, with no
    /// time zone: the system fires it at that local time wherever the device
    /// is (spec §5.2).
    public let trigger: DateComponents
    public let title: String
    public let body: String
    /// Groups notifications in Notification Center.
    public let threadID: String

    public var itemID: UUID? {
        if case .due(let id) = kind { return id }
        return nil
    }

    /// Where tapping the notification goes.
    public var link: DeepLink {
        switch kind {
        case .due(let id): .item(id)
        case .morningSummary: .upcoming
        }
    }

    /// Changes whenever anything shown or scheduled changes; kept in the
    /// request's `userInfo` so an unchanged request isn't re-added.
    public var fingerprint: String {
        let when = [trigger.era, trigger.year, trigger.month, trigger.day, trigger.hour, trigger.minute]
            .map { $0.map(String.init) ?? "-" }
            .joined(separator: ":")
        return StableHash.fnv1a64([id, category.rawValue, when, title, body, threadID, link.url.absoluteString].joined(separator: "\u{1F}"))
    }

    /// `userInfo` keys on scheduled requests.
    public enum UserInfoKey {
        public static let fingerprint = "fingerprint"
        public static let link = "link"
        public static let itemID = "itemID"
    }

    static let itemPrefix = "item."
    static let summaryPrefix = "summary."

    /// The request identifier of an item's due-time alert — pending or
    /// delivered. Other processes use it to withdraw the alert, e.g. after
    /// completing the task from a widget.
    public static func identifier(forItem itemID: UUID) -> String {
        itemPrefix + itemID.uuidString
    }

    /// The request identifier of one day's morning summary.
    public static func identifier(forSummaryOn day: LocalDay) -> String {
        summaryPrefix + day.isoString
    }

    /// The item an alert's request identifier points at.
    public static func itemID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(itemPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(itemPrefix.count)))
    }

    /// True for identifiers the planner owns; anything else pending is left alone.
    public static func isPlannerIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(itemPrefix) || identifier.hasPrefix(summaryPrefix)
    }
}

/// A hash that is the same in every process and on every launch (unlike
/// `Hasher`), for comparing against what an earlier launch scheduled.
enum StableHash {
    /// 64-bit FNV-1a of the UTF-8 bytes, as 16 lowercase hex digits.
    static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
