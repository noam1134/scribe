import Foundation
import Observation

public enum ItemFilter: Hashable, Sendable {
    case inbox
    case category(UUID)
    /// Title + body, case/diacritic-insensitive, includes done items.
    case search(String)
    /// Every item, done ones included.
    case all
}

public struct ItemDraft: Equatable, Sendable {
    public var title: String
    public var body: String
    public var kind: ItemKind
    public var categoryID: UUID?
    public var due: DueDate?

    public init(title: String, body: String = "", kind: ItemKind = .task, categoryID: UUID? = nil, due: DueDate? = nil) {
        self.title = title
        self.body = body
        self.kind = kind
        self.categoryID = categoryID
        self.due = due
    }
}

/// The editable fields of an item, handed to `updateItem`'s closure.
public struct ItemEdit: Equatable, Sendable {
    public var title: String
    public var body: String
    public var kind: ItemKind
    public var categoryID: UUID?
    public var due: DueDate?
    /// Replaced as a whole.
    public var checklist: [ChecklistItem]

    public init(title: String, body: String, kind: ItemKind, categoryID: UUID?, due: DueDate?, checklist: [ChecklistItem] = []) {
        self.title = title
        self.body = body
        self.kind = kind
        self.categoryID = categoryID
        self.due = due
        self.checklist = checklist
    }
}

public struct CategoryDraft: Equatable, Sendable {
    public var name: String
    public var emoji: String
    public var colorName: String

    public init(name: String, emoji: String = "", colorName: String = CategoryPalette.defaultColorName) {
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
    }
}

public struct CategoryEdit: Equatable, Sendable {
    public var name: String
    public var emoji: String
    public var colorName: String

    public init(name: String, emoji: String, colorName: String) {
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
    }
}

/// What `deleteCategory` removed — everything `restoreCategory` needs.
public struct CategoryDeletion: Equatable, Sendable {
    public let category: CategorySnapshot
    public let itemIDs: [UUID]

    public init(category: CategorySnapshot, itemIDs: [UUID]) {
        self.category = category
        self.itemIDs = itemIDs
    }
}

public enum StoreError: Error, Equatable {
    case emptyTitle
    case emptyCategoryName
    case duplicateCategoryName
    case invalidColorName(String)
    case itemNotFound(UUID)
    case categoryNotFound(UUID)
}

/// The only way UI, widgets and intents touch data. v1 implementation:
/// `SwiftDataItemStore`. A future `CloudflareItemStore` conforms to the same protocol.
@MainActor
public protocol ItemStore: AnyObject, Observable {
    /// Sorted by `sortIndex`.
    var categories: [CategorySnapshot] { get }
    func items(_ filter: ItemFilter) -> [ItemSnapshot]
    func item(_ id: UUID) -> ItemSnapshot?
    /// Open tasks and memos that have a date — everything an agenda can
    /// show at any moment, without the done tasks that pile up over time.
    /// For widgets, which must stay small. Sorted by due date.
    func datedOpenItems() -> [ItemSnapshot]
    func agenda(_ scope: CategoryScope, now: Date) -> Agenda

    @discardableResult func addItem(_ draft: ItemDraft) throws -> UUID
    func updateItem(_ id: UUID, _ edit: (inout ItemEdit) -> Void) throws
    /// No-op for memos.
    func setDone(_ id: UUID, _ done: Bool) throws
    func deleteItem(_ id: UUID) throws
    /// Re-inserts a deleted item (Undo). No-op if the id still exists.
    func restoreItem(_ snapshot: ItemSnapshot) throws

    @discardableResult func addCategory(_ draft: CategoryDraft) throws -> UUID
    func updateCategory(_ id: UUID, _ edit: (inout CategoryEdit) -> Void) throws
    /// `index` is the category's final position in the sorted list (clamped).
    func moveCategory(_ id: UUID, toIndex index: Int) throws
    /// Same meaning as SwiftUI's `onMove(perform:)`: `destination` is an index
    /// in the list *before* the move.
    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) throws
    /// Items in the category move to the Inbox. Keep the result to undo.
    @discardableResult func deleteCategory(_ id: UUID) throws -> CategoryDeletion
    /// Undo for `deleteCategory`: same id, name, color and position; items
    /// that are still in the Inbox go back into it. No-op if it exists.
    func restoreCategory(_ deletion: CategoryDeletion) throws

    func exportJSON() throws -> Data
    /// Re-read everything (after a sync import or a write by another process).
    func refresh()
}
