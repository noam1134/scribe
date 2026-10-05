import Foundation

/// A keyboard command in the Mac window (spec §9.3).
public enum ListCommand: Hashable, Sendable {
    /// ⌘N
    case newItem
    /// Space
    case toggleDone
    /// ⌘⌫ (and ⌫)
    case delete
    /// Return or double-click: open the row's inline editor.
    case edit
    /// ⌘0–⌘9
    case jump(Int)
    /// ⌘F
    case find
}

/// What the window looks like when a command arrives.
public struct ListCommandContext: Sendable {
    public var listIsFocused: Bool
    public var isEditingText: Bool
    public var selectedItem: ItemSnapshot?
    public var categories: [CategorySnapshot]

    public init(listIsFocused: Bool, isEditingText: Bool, selectedItem: ItemSnapshot?, categories: [CategorySnapshot]) {
        self.listIsFocused = listIsFocused
        self.isEditingText = isEditingText
        self.selectedItem = selectedItem
        self.categories = categories
    }
}

public enum ListCommandAction: Equatable, Sendable {
    case startQuickAdd
    case setDone(UUID, Bool)
    case delete(ItemSnapshot)
    case edit(UUID)
    case show(SidebarEntry)
    case focusSearch
}

public enum ListCommands {
    /// What a command does, or nil when it doesn't apply. Space, Return and
    /// ⌘⌫ act on the selected row only while the list has focus and no text
    /// is being edited; ⌘N, ⌘F and ⌘0–⌘9 work anywhere in the window.
    public static func action(for command: ListCommand, in context: ListCommandContext) -> ListCommandAction? {
        switch command {
        case .newItem:
            return .startQuickAdd
        case .find:
            return .focusSearch
        case .jump(let digit):
            return Sidebar.entry(forShortcutDigit: digit, categories: context.categories).map(ListCommandAction.show)
        case .toggleDone, .delete, .edit:
            guard context.listIsFocused, !context.isEditingText, let item = context.selectedItem else { return nil }
            switch command {
            case .toggleDone: return item.kind == .task ? .setDone(item.id, !item.isDone) : nil
            case .delete: return .delete(item)
            default: return .edit(item.id)
            }
        }
    }
}

public enum ListSelection {
    /// The row to select when `id` leaves a list shown in `order`: the next
    /// one, else the previous one.
    public static func afterRemoving(_ id: UUID, from order: [UUID]) -> UUID? {
        guard let index = order.firstIndex(of: id) else { return nil }
        if index + 1 < order.count { return order[index + 1] }
        return index > 0 ? order[index - 1] : nil
    }
}
