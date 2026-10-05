import AppKit
import Observation
import ScribeCore

/// State of one Mac window: what the sidebar shows, the selected and the
/// expanded row, search, keyboard focus requests and the "Couldn’t Save"
/// alert. Keyboard and menu commands land here (spec §9.3).
@MainActor
@Observable
final class MacRouter {
    enum Focus: Hashable {
        case list, quickAdd, search
    }

    let store: any ItemStore

    var sidebar: SidebarEntry = .upcoming {
        didSet {
            guard sidebar != oldValue else { return }
            selectedItemID = nil
            expandedItemID = nil
            showsDone = false
            searchText = ""
        }
    }

    var selectedItemID: UUID? {
        didSet {
            // Selecting another row closes the one being edited.
            if let expandedItemID, expandedItemID != selectedItemID { self.expandedItemID = nil }
        }
    }

    /// The row showing its inline editor; one at a time.
    var expandedItemID: UUID?
    /// Whether the category list's Done group is open.
    var showsDone = false
    var searchText = ""
    var alertMessage: String?
    /// Where the root should move keyboard focus next; it clears this.
    var focusRequest: Focus?
    /// Where keyboard focus is, as the root last saw it.
    var focus: Focus?
    /// The item rows in on-screen order, kept by the list.
    var visibleItemIDs: [UUID] = []
    @ObservationIgnored weak var undoManager: UndoManager?

    init(store: any ItemStore) {
        self.store = store
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Runs a store write; failures become an alert instead of vanishing.
    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Store writes that ⌘Z can undo.
    var undoable: StoreUndo {
        StoreUndo(store: store, manager: undoManager) { [weak self] error in
            self?.alertMessage = error.localizedDescription
        }
    }

    // MARK: Commands

    /// Whether a command would do something now (menu item state).
    func canRun(_ command: ListCommand) -> Bool {
        ListCommands.action(for: command, in: context) != nil
    }

    /// Runs a keyboard or menu command; false when it doesn't apply.
    @discardableResult
    func run(_ command: ListCommand) -> Bool {
        guard let action = ListCommands.action(for: command, in: context) else { return false }
        switch action {
        case .startQuickAdd:
            focusRequest = .quickAdd
        case .focusSearch:
            focusRequest = .search
        case .show(let entry):
            sidebar = entry
            searchText = ""
            focusRequest = .list
        case .edit(let id):
            expandedItemID = id
        case .setDone(let id, let done):
            if let item = store.item(id) { setDone(item, done) }
        case .delete(let item):
            delete(item)
        }
        return true
    }

    /// ⌘⌫ from the menu. A text field keeps its own ⌘⌫ (delete to the start
    /// of the line): a menu shortcut would otherwise swallow it.
    func deleteCommand() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            text.deleteToBeginningOfLine(nil)
        } else if !run(.delete) {
            NSSound.beep()
        }
    }

    private var context: ListCommandContext {
        ListCommandContext(
            listIsFocused: focus == .list,
            isEditingText: expandedItemID != nil || NSApp.keyWindow?.firstResponder is NSText,
            selectedItem: selectedItemID.flatMap { store.item($0) },
            categories: store.categories
        )
    }

    // MARK: Writes

    func setDone(_ item: ItemSnapshot, _ done: Bool) {
        perform { try undoable.setDone(item, done) }
    }

    func delete(_ item: ItemSnapshot) {
        perform {
            try undoable.deleteItem(item)
            if expandedItemID == item.id { expandedItemID = nil }
        }
    }

    func update(_ item: ItemSnapshot, _ actionName: String, _ edit: (inout ItemEdit) -> Void) {
        perform { try undoable.update(item.id, actionName: actionName, edit) }
    }

    func closeEditor() {
        expandedItemID = nil
        focusRequest = .list
    }

    // MARK: Links

    func open(_ link: DeepLink) {
        searchText = ""
        switch link {
        case .upcoming:
            sidebar = .upcoming
        case .add(let categoryID):
            if let categoryID, store.categories.contains(where: { $0.id == categoryID }) {
                sidebar = .category(categoryID)
            }
            focusRequest = .quickAdd
        case .item(let id):
            guard let item = store.item(id) else { return }
            sidebar = item.categoryID.map(SidebarEntry.category) ?? .inbox
            showsDone = item.isDone
            selectedItemID = id
            expandedItemID = id
        }
    }
}
