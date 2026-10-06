import Foundation

/// Store writes that can be undone and redone through an `UndoManager` —
/// the Mac's Edit › Undo / ⌘Z (spec §13). Each write registers its inverse,
/// and each inverse registers the write again, so redo works too.
@MainActor
public struct StoreUndo {
    public let store: any ItemStore
    /// Weak: the manager keeps these handlers, which keep a copy of this.
    public private(set) weak var manager: UndoManager?
    /// An undo or redo that can no longer apply (the item was deleted on
    /// another device, say). Writes made directly throw instead.
    public let onError: @MainActor (any Error) -> Void

    public init(store: any ItemStore, manager: UndoManager?, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.store = store
        self.manager = manager
        self.onError = onError
    }

    public func deleteItem(_ item: ItemSnapshot) throws {
        try store.deleteItem(item.id)
        register(Self.deleteName(item.title)) { try $0.restoreItem(item) }
    }

    public func setDone(_ item: ItemSnapshot, _ done: Bool) throws {
        try store.setDone(item.id, done)
        register(done ? "Mark as Done" : "Mark as Not Done") { try $0.setDone(item, !done) }
    }

    @discardableResult
    public func deleteCategory(_ id: UUID) throws -> CategoryDeletion {
        let deletion = try store.deleteCategory(id)
        register(Self.deleteName(deletion.category.name)) { try $0.restoreCategory(deletion) }
        return deletion
    }

    /// Any edit. Undo and redo touch only the fields this edit changed, so
    /// a later rename (here or on another device) survives undoing a move.
    public func update(_ id: UUID, actionName: String, _ edit: (inout ItemEdit) -> Void) throws {
        guard let before = store.item(id) else { throw StoreError.itemNotFound(id) }
        try store.updateItem(id, edit)
        guard let after = store.item(id) else { return }
        let change = FieldChange(from: before, to: after)
        guard !change.isEmpty else { return }
        register(actionName) { try $0.apply(change.reversed, to: id, actionName: actionName) }
    }

    // MARK: Inverses

    private func restoreItem(_ item: ItemSnapshot) throws {
        try store.restoreItem(item)
        register(Self.deleteName(item.title)) { try $0.deleteItem(item) }
    }

    private func restoreCategory(_ deletion: CategoryDeletion) throws {
        try store.restoreCategory(deletion)
        register(Self.deleteName(deletion.category.name)) { try $0.deleteCategory(deletion.category.id) }
    }

    private func apply(_ change: FieldChange, to id: UUID, actionName: String) throws {
        guard store.item(id) != nil else { throw StoreError.itemNotFound(id) }
        try store.updateItem(id) { change.apply(to: &$0) }
        // After the kind: a memo can't be done.
        if let done = change.isDone { try store.setDone(id, done) }
        register(actionName) { try $0.apply(change.reversed, to: id, actionName: actionName) }
    }

    // MARK: Helpers

    private func register(_ actionName: String, _ inverse: @escaping @MainActor (StoreUndo) throws -> Void) {
        guard let manager else { return }
        let undo = self
        manager.registerUndo(withTarget: store) { _ in
            do {
                try inverse(undo)
            } catch {
                undo.onError(error)
            }
        }
        manager.setActionName(actionName)
    }

    private static func deleteName(_ name: String) -> String {
        "Delete “\(name)”"
    }
}

/// The fields one edit changed: their values before and after. Done counts
/// too — making a done task a memo clears it, and undo brings it back.
private struct FieldChange {
    struct Values {
        var title: String?
        var body: String?
        var kind: ItemKind?
        var categoryID: UUID??
        var due: DueDate??
        var isDone: Bool?
        var checklist: [ChecklistItem]?
    }

    var old = Values()
    var new = Values()

    init(from before: ItemSnapshot, to after: ItemSnapshot) {
        if before.title != after.title { (old.title, new.title) = (before.title, after.title) }
        if before.body != after.body { (old.body, new.body) = (before.body, after.body) }
        if before.kind != after.kind { (old.kind, new.kind) = (before.kind, after.kind) }
        if before.categoryID != after.categoryID { (old.categoryID, new.categoryID) = (.some(before.categoryID), .some(after.categoryID)) }
        if before.due != after.due { (old.due, new.due) = (.some(before.due), .some(after.due)) }
        if before.isDone != after.isDone { (old.isDone, new.isDone) = (before.isDone, after.isDone) }
        if before.checklist != after.checklist { (old.checklist, new.checklist) = (before.checklist, after.checklist) }
    }

    private init(old: Values, new: Values) {
        self.old = old
        self.new = new
    }

    var isEmpty: Bool {
        new.title == nil && new.body == nil && new.kind == nil && new.categoryID == nil && new.due == nil && new.isDone == nil
            && new.checklist == nil
    }

    /// Undo for this change (and redo for the undo).
    var reversed: FieldChange { FieldChange(old: new, new: old) }

    /// The done state to set after `apply`, if it changed.
    var isDone: Bool? { new.isDone }

    func apply(to edit: inout ItemEdit) {
        if let title = new.title { edit.title = title }
        if let body = new.body { edit.body = body }
        if let kind = new.kind { edit.kind = kind }
        if let categoryID = new.categoryID { edit.categoryID = categoryID }
        if let due = new.due { edit.due = due }
        if let checklist = new.checklist { edit.checklist = checklist }
    }
}
