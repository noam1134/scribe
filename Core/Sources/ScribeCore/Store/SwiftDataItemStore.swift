import Foundation
import Observation
import SwiftData

/// `ItemStore` backed by SwiftData (+ CloudKit when the container syncs).
/// Every call uses a fresh `ModelContext`, so reads always see the latest
/// file contents, including writes made by the widget or intents.
@MainActor
@Observable
public final class SwiftDataItemStore: ItemStore {
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// Bumped after every write and on `refresh()`. Every read touches it,
    /// so SwiftUI views re-render when it changes.
    private var revision = 0

    public init(container: ModelContainer, calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.calendar = calendar
        self.now = now
    }

    // MARK: Reads

    public var categories: [CategorySnapshot] {
        _ = revision
        let context = ModelContext(container)
        var openCounts: [UUID: Int] = [:]
        for item in fetchItems(context).map(\.snapshot) where !item.isDone {
            if let id = item.categoryID { openCounts[id, default: 0] += 1 }
        }
        return fetchCategories(context).map { $0.snapshot(openCount: openCounts[$0.id] ?? 0) }
    }

    public func items(_ filter: ItemFilter) -> [ItemSnapshot] {
        _ = revision
        let all = fetchItems(ModelContext(container)).map(\.snapshot)
        switch filter {
        case .inbox:
            return all.filter { $0.categoryID == nil }.sorted(by: ItemOrdering.list)
        case .category(let id):
            return all.filter { $0.categoryID == id }.sorted(by: ItemOrdering.list)
        case .search(let query):
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return [] }
            return all
                .filter { $0.title.localizedStandardContains(query) || $0.body.localizedStandardContains(query) }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func item(_ id: UUID) -> ItemSnapshot? {
        _ = revision
        return try? itemModel(id, in: ModelContext(container)).snapshot
    }

    public func agenda(_ scope: CategoryScope, now: Date) -> Agenda {
        _ = revision
        let all = fetchItems(ModelContext(container)).map(\.snapshot)
        return AgendaBuilder.build(items: all, scope: scope, now: now, calendar: calendar)
    }

    // MARK: Items

    @discardableResult
    public func addItem(_ draft: ItemDraft) throws -> UUID {
        let context = ModelContext(container)
        let title = try Self.validTitle(draft.title)
        let category = try draft.categoryID.map { try categoryModel($0, in: context) }
        let stamp = now()
        let item = Item(title: title, body: draft.body, kind: draft.kind, due: draft.due, createdAt: stamp, updatedAt: stamp)
        context.insert(item)
        item.category = category
        try save(context)
        return item.id
    }

    public func updateItem(_ id: UUID, _ edit: (inout ItemEdit) -> Void) throws {
        let context = ModelContext(container)
        let item = try itemModel(id, in: context)
        var fields = ItemEdit(title: item.title, body: item.body, kind: item.kind, categoryID: item.category?.id, due: item.due)
        edit(&fields)
        let title = try Self.validTitle(fields.title)
        let category = try fields.categoryID.map { try categoryModel($0, in: context) }
        item.title = title
        item.body = fields.body
        item.kind = fields.kind
        if fields.kind == .memo {
            item.isDone = false
            item.doneAt = nil
        }
        item.category = category
        item.due = fields.due
        item.updatedAt = now()
        try save(context)
    }

    public func setDone(_ id: UUID, _ done: Bool) throws {
        let context = ModelContext(container)
        let item = try itemModel(id, in: context)
        guard item.kind == .task, item.isDone != done else { return }
        let stamp = now()
        item.isDone = done
        item.doneAt = done ? stamp : nil
        item.updatedAt = stamp
        try save(context)
    }

    public func deleteItem(_ id: UUID) throws {
        let context = ModelContext(container)
        context.delete(try itemModel(id, in: context))
        try save(context)
    }

    public func restoreItem(_ snapshot: ItemSnapshot) throws {
        let context = ModelContext(container)
        guard (try? itemModel(snapshot.id, in: context)) == nil else { return }
        let item = Item(
            id: snapshot.id,
            title: snapshot.title,
            body: snapshot.body,
            kind: snapshot.kind,
            due: snapshot.due,
            isDone: snapshot.isDone,
            doneAt: snapshot.doneAt,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        context.insert(item)
        item.category = snapshot.categoryID.flatMap { try? categoryModel($0, in: context) }
        try save(context)
    }

    // MARK: Categories

    @discardableResult
    public func addCategory(_ draft: CategoryDraft) throws -> UUID {
        let context = ModelContext(container)
        let name = try validCategoryName(draft.name, excluding: nil, in: context)
        try Self.validateColor(draft.colorName)
        let nextIndex = (fetchCategories(context).last?.sortIndex ?? -1) + 1
        let category = Category(name: name, emoji: draft.emoji, colorName: draft.colorName, sortIndex: nextIndex)
        context.insert(category)
        try save(context)
        return category.id
    }

    public func updateCategory(_ id: UUID, _ edit: (inout CategoryEdit) -> Void) throws {
        let context = ModelContext(container)
        let category = try categoryModel(id, in: context)
        var fields = CategoryEdit(name: category.name, emoji: category.emoji, colorName: category.colorName)
        edit(&fields)
        let name = try validCategoryName(fields.name, excluding: id, in: context)
        try Self.validateColor(fields.colorName)
        category.name = name
        category.emoji = fields.emoji
        category.colorName = fields.colorName
        try save(context)
    }

    public func moveCategory(_ id: UUID, toIndex index: Int) throws {
        let context = ModelContext(container)
        var ordered = fetchCategories(context)
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { throw StoreError.categoryNotFound(id) }
        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: min(max(index, 0), ordered.count))
        for (position, category) in ordered.enumerated() where category.sortIndex != Double(position) {
            category.sortIndex = Double(position)
        }
        try save(context)
    }

    public func deleteCategory(_ id: UUID) throws {
        let context = ModelContext(container)
        context.delete(try categoryModel(id, in: context))
        try save(context)
    }

    // MARK: Export & refresh

    public func exportJSON() throws -> Data {
        let context = ModelContext(container)
        let document = ExportDocument(
            version: ExportDocument.currentVersion,
            exportedAt: now(),
            categories: fetchCategories(context).map {
                ExportedCategory(id: $0.id, name: $0.name, emoji: $0.emoji, colorName: $0.colorName, sortIndex: $0.sortIndex)
            },
            items: fetchItems(context).sorted { $0.createdAt < $1.createdAt }.map {
                ExportedItem(
                    id: $0.id, title: $0.title, body: $0.body, kind: $0.kind, categoryID: $0.category?.id,
                    dueDay: $0.dueDay, dueMinute: $0.dueMinute, isDone: $0.isDone, doneAt: $0.doneAt,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }
        )
        return try ExportDocument.encoder().encode(document)
    }

    public func refresh() {
        revision += 1
    }

    // MARK: Helpers

    private func save(_ context: ModelContext) throws {
        try context.save()
        revision += 1
    }

    private func fetchItems(_ context: ModelContext) -> [Item] {
        do {
            return try context.fetch(FetchDescriptor<Item>())
        } catch {
            assertionFailure("Item fetch failed: \(error)")
            return []
        }
    }

    private func fetchCategories(_ context: ModelContext) -> [Category] {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)])
        do {
            return try context.fetch(descriptor)
        } catch {
            assertionFailure("Category fetch failed: \(error)")
            return []
        }
    }

    private func itemModel(_ id: UUID, in context: ModelContext) throws -> Item {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try context.fetch(descriptor).first else { throw StoreError.itemNotFound(id) }
        return item
    }

    private func categoryModel(_ id: UUID, in context: ModelContext) throws -> Category {
        var descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let category = try context.fetch(descriptor).first else { throw StoreError.categoryNotFound(id) }
        return category
    }

    private static func validTitle(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        return title
    }

    private func validCategoryName(_ raw: String, excluding id: UUID?, in context: ModelContext) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.emptyCategoryName }
        let key = TextNormalizer.key(name)
        if fetchCategories(context).contains(where: { $0.id != id && TextNormalizer.key($0.name) == key }) {
            throw StoreError.duplicateCategoryName
        }
        return name
    }

    private static func validateColor(_ name: String) throws {
        guard CategoryPalette.colorNames.contains(name) else { throw StoreError.invalidColorName(name) }
    }
}
