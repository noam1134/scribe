import AppIntents
import ScribeCore

/// A category, for the widget's and the Control's configuration and for
/// Siri asking where an item goes (spec §8).
struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryQuery()

    let id: UUID
    let name: String

    init(_ category: CategorySnapshot) {
        id = category.id
        name = category.name
    }

    /// The name alone: Siri reads it aloud, so no emoji.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CategoryQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        let wanted = Set(identifiers)
        return try SharedStore.openForIntent().categories.filter { wanted.contains($0.id) }.map(CategoryEntity.init)
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
