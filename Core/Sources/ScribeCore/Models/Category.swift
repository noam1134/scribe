import Foundation
import SwiftData

@Model
final class Category {
    public var id: UUID = UUID()
    public var name: String = ""
    public var emoji: String = ""
    public var colorName: String = CategoryPalette.defaultColorName
    public var sortIndex: Double = 0
    /// Deleting a category nullifies `Item.category`, moving items to the Inbox.
    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    public var items: [Item]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "",
        colorName: String = CategoryPalette.defaultColorName,
        sortIndex: Double = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
        self.sortIndex = sortIndex
    }
}
