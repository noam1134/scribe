import Foundation

/// A section of the iPhone's Lists screen (spec §20): the Inbox or one category.
public enum ListSectionID: Hashable, Sendable {
    case inbox
    case category(UUID)

    /// How the per-device collapse state stores it.
    public var storageKey: String {
        switch self {
        case .inbox: "inbox"
        case .category(let id): id.uuidString
        }
    }

    public init?(storageKey: String) {
        if storageKey == "inbox" {
            self = .inbox
        } else if let id = UUID(uuidString: storageKey) {
            self = .category(id)
        } else {
            return nil
        }
    }
}

public struct ListSection: Identifiable, Equatable, Sendable {
    public let id: ListSectionID
    /// nil for the Inbox.
    public let category: CategorySnapshot?
    /// Open tasks, then memos, then the done items on show.
    public let items: [ItemSnapshot]
    /// Open tasks and memos.
    public let openCount: Int
}

public enum ListSections {
    /// The Inbox first while it shows something, then every category in
    /// sort order, empty ones too. Done items show when `showsCompleted`;
    /// the `keeping` item (the one being edited) shows either way.
    public static func make(
        items: [ItemSnapshot],
        categories: [CategorySnapshot],
        showsCompleted: Bool,
        keeping keptID: UUID? = nil
    ) -> [ListSection] {
        let sorted = categories.sorted { $0.sortIndex < $1.sortIndex }
        let grouped = Dictionary(grouping: items) { sectionID(for: $0, categories: sorted) }

        func section(_ id: ListSectionID, _ category: CategorySnapshot?) -> ListSection {
            let contents = CategoryContents(items: grouped[id] ?? [])
            let done = showsCompleted ? contents.done : contents.done.filter { $0.id == keptID }
            let open = contents.openTasks + contents.memos
            return ListSection(id: id, category: category, items: open + done, openCount: open.count)
        }

        var sections: [ListSection] = []
        let inbox = section(.inbox, nil)
        if !inbox.items.isEmpty { sections.append(inbox) }
        sections += sorted.map { section(.category($0.id), $0) }
        return sections
    }

    /// Where `item` shows: its category, or the Inbox when it has none (or
    /// one that isn't in `categories`).
    public static func sectionID(for item: ItemSnapshot, categories: [CategorySnapshot]) -> ListSectionID {
        guard let id = item.categoryID, categories.contains(where: { $0.id == id }) else { return .inbox }
        return .category(id)
    }
}
