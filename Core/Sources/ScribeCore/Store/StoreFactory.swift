import SwiftData

public enum StoreFactory {
    public static var schema: Schema { Schema([Item.self, Category.self]) }

    /// Fresh, empty, in-memory store. For tests and previews.
    public static func inMemory() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// The real store in the App Group container. Only the main app syncs
    /// with CloudKit; the widget extension and intents pass `false`.
    public static func shared(syncsWithCloudKit: Bool) throws -> ModelContainer {
        let config = ModelConfiguration(
            "Scribe",
            schema: schema,
            groupContainer: .identifier(ScribeIDs.appGroup),
            cloudKitDatabase: syncsWithCloudKit ? .private(ScribeIDs.cloudKitContainer) : .none
        )
        return try ModelContainer(for: schema, configurations: config)
    }
}
