import AppIntents
import ScribeCore

/// A category, for the widget's and the Control's configuration and for
/// Siri asking where an item goes (spec §8).
struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryQuery()

    let id: UUID
    let name: String
    /// A configuration still points at this category, but it was deleted.
    let isDeleted: Bool

    init(_ category: CategorySnapshot) {
        id = category.id
        name = category.name
        isDeleted = false
    }

    /// Stands in for a deleted category, so a configured widget can say so
    /// instead of quietly showing every category.
    static func deleted(_ id: UUID) -> CategoryEntity {
        CategoryEntity(id: id, name: "Deleted category", isDeleted: true)
    }

    private init(id: UUID, name: String, isDeleted: Bool) {
        self.id = id
        self.name = name
        self.isDeleted = isDeleted
    }

    /// The id to file into or open; nil once the category is gone.
    var liveID: UUID? { isDeleted ? nil : id }

    /// The name alone: Siri reads it aloud, so no emoji.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CategoryQuery: EntityStringQuery {
    /// How the system turns saved configurations back into categories.
    /// Deleted ones come back as placeholders rather than not at all.
    @MainActor
    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        let categories = try SharedStore.openForIntent().categories
        return CategoryLookup.categories(withIDs: identifiers, in: categories).map { found in
            found.category.map(CategoryEntity.init) ?? .deleted(found.id)
        }
    }

    /// What Siri heard, or what was typed into a picker's search field.
    @MainActor
    func entities(matching string: String) async throws -> [CategoryEntity] {
        IntentAdd.categories(matching: string, in: try SharedStore.openForIntent().categories).map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        try SharedStore.openForIntent().categories.map(CategoryEntity.init)
    }
}
