import Foundation

/// Finds the categories behind ids that widgets, controls and shortcuts
/// saved in their configuration.
public enum CategoryLookup {
    public struct Found: Equatable, Sendable {
        public let id: UUID
        /// nil: deleted here or on another device.
        public let category: CategorySnapshot?
    }

    /// One result per id, in order. A deleted category is reported rather
    /// than dropped: dropping it would turn a widget configured for that
    /// category into an "all categories" widget without a word.
    public static func categories(withIDs ids: [UUID], in categories: [CategorySnapshot]) -> [Found] {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.map { Found(id: $0, category: byID[$0]) }
    }
}
