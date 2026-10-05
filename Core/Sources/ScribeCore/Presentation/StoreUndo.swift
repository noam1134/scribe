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

    /// Any edit; undo puts back every field as it was just before.
    public func update(_ id: UUID, actionName: String, _ edit: (inout ItemEdit) -> Void) throws {
        guard let before = store.item(id) else { throw StoreError.itemNotFound(id) }
        try store.updateItem(id, edit)
        register(actionName) { try $0.setFields(id, Self.fields(of: before), actionName: actionName) }
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

    private func setFields(_ id: UUID, _ fields: ItemEdit, actionName: String) throws {
        guard let current = store.item(id) else { throw StoreError.itemNotFound(id) }
        try store.updateItem(id) { $0 = fields }
        register(actionName) { try $0.setFields(id, Self.fields(of: current), actionName: actionName) }
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

    private static func fields(of item: ItemSnapshot) -> ItemEdit {
        ItemEdit(title: item.title, body: item.body, kind: item.kind, categoryID: item.categoryID, due: item.due)
    }

    private static func deleteName(_ name: String) -> String {
        "Delete “\(name)”"
    }
}
