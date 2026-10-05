import Foundation

/// The three sections of a category screen (spec §9.2): open tasks, memos,
/// then done tasks (most recently completed first).
public struct CategoryContents: Equatable, Sendable {
    public var openTasks: [ItemSnapshot]
    public var memos: [ItemSnapshot]
    public var done: [ItemSnapshot]

    /// `items` keeps the store's list order for open tasks and memos.
    public init(items: [ItemSnapshot]) {
        openTasks = items.filter { $0.kind == .task && !$0.isDone }
        memos = items.filter { $0.kind == .memo }
        done = items
            .filter { $0.isDone }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    public var isEmpty: Bool { openTasks.isEmpty && memos.isEmpty && done.isEmpty }
}

/// Search results grouped by where they live: Inbox first, then categories
/// in their sort order; empty groups are left out.
public struct SearchGroup: Identifiable, Equatable, Sendable {
    /// nil for the Inbox.
    public let category: CategorySnapshot?
    public let items: [ItemSnapshot]

    public var id: String { category?.id.uuidString ?? "inbox" }

    public static func make(items: [ItemSnapshot], categories: [CategorySnapshot]) -> [SearchGroup] {
        var groups: [SearchGroup] = []
        let inbox = items.filter { $0.categoryID == nil }
        if !inbox.isEmpty { groups.append(SearchGroup(category: nil, items: inbox)) }
        for category in categories.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let matches = items.filter { $0.categoryID == category.id }
            if !matches.isEmpty { groups.append(SearchGroup(category: category, items: matches)) }
        }
        return groups
    }
}
