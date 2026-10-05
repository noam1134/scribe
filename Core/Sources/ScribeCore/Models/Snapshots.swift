import Foundation

/// Value copy of an item. UI, widgets and intents only ever see snapshots,
/// never SwiftData models — this is what keeps the backend swappable.
public struct ItemSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var kind: ItemKind
    public var categoryID: UUID?
    public var due: DueDate?
    public var isDone: Bool
    public var doneAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        kind: ItemKind = .task,
        categoryID: UUID? = nil,
        due: DueDate? = nil,
        isDone: Bool = false,
        doneAt: Date? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.categoryID = categoryID
        self.due = due
        self.isDone = isDone
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CategorySnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var colorName: String
    public var sortIndex: Double
    /// Items in this category that are not done (open tasks + memos).
    public var openCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "",
        colorName: String = CategoryPalette.defaultColorName,
        sortIndex: Double = 0,
        openCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
        self.sortIndex = sortIndex
        self.openCount = openCount
    }
}

extension Item {
    var snapshot: ItemSnapshot {
        ItemSnapshot(
            id: id,
            title: title,
            body: body,
            kind: kind,
            categoryID: category?.id,
            due: due,
            isDone: kind == .task && isDone,
            doneAt: doneAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Category {
    func snapshot(openCount: Int) -> CategorySnapshot {
        CategorySnapshot(id: id, name: name, emoji: emoji, colorName: colorName, sortIndex: sortIndex, openCount: openCount)
    }
}
