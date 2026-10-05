import Foundation

/// A row of the Mac sidebar (spec §9.3).
public enum SidebarEntry: Hashable, Sendable {
    case upcoming
    case inbox
    case category(UUID)

    /// The items the list shows; nil for Upcoming, which shows the agenda.
    public var filter: ItemFilter? {
        switch self {
        case .upcoming: nil
        case .inbox: .inbox
        case .category(let id): .category(id)
        }
    }

    /// The category on screen, which quick-add preselects (spec §19).
    public var categoryID: UUID? {
        if case .category(let id) = self { return id }
        return nil
    }
}

public enum Sidebar {
    /// The Inbox row shows while something is in it (spec §19) — and while
    /// it is selected, so it doesn't vanish when its last item moves out.
    public static func showsInbox(itemCount: Int, selection: SidebarEntry) -> Bool {
        itemCount > 0 || selection == .inbox
    }

    /// ⌘0 shows Upcoming; ⌘1–⌘9 the first nine categories in sidebar order.
    public static func entry(forShortcutDigit digit: Int, categories: [CategorySnapshot]) -> SidebarEntry? {
        switch digit {
        case 0: .upcoming
        case 1...9 where digit <= categories.count: .category(categories[digit - 1].id)
        default: nil
        }
    }

    /// The ⌘ digit that shows this category, if it is one of the first nine.
    public static func shortcutDigit(for categoryID: UUID, categories: [CategorySnapshot]) -> Int? {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }), index < 9 else { return nil }
        return index + 1
    }

    /// A category that no longer exists (deleted on another device) falls
    /// back to Upcoming.
    public static func validated(_ selection: SidebarEntry, categories: [CategorySnapshot]) -> SidebarEntry {
        guard case .category(let id) = selection, !categories.contains(where: { $0.id == id }) else { return selection }
        return .upcoming
    }

    /// Where the selection goes when the selected category is deleted: the
    /// next category, else the previous one, else Upcoming. `categories` is
    /// the list before the delete.
    public static func selection(afterDeleting id: UUID, from categories: [CategorySnapshot]) -> SidebarEntry {
        let ids = categories.map(\.id)
        return ListSelection.afterRemoving(id, from: ids).map(SidebarEntry.category) ?? .upcoming
    }
}
