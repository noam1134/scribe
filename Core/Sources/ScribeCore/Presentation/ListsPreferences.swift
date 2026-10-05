import Foundation

/// The Lists screen's state on this device (spec §20): which sections are
/// collapsed and whether done items show. Never synced. Sections are stored
/// by what is collapsed, so a new category starts expanded.
public struct ListsPreferences: Equatable, Sendable {
    public enum Keys {
        public static let collapsed = "lists.collapsed"
        public static let showsCompleted = "lists.showsCompleted"
    }

    public var showsCompleted: Bool
    private var collapsed: Set<ListSectionID>

    public init(showsCompleted: Bool = false) {
        self.showsCompleted = showsCompleted
        collapsed = []
    }

    public func isCollapsed(_ id: ListSectionID) -> Bool {
        collapsed.contains(id)
    }

    public mutating func toggle(_ id: ListSectionID) {
        if collapsed.remove(id) == nil { collapsed.insert(id) }
    }

    public mutating func expand(_ id: ListSectionID) {
        collapsed.remove(id)
    }

    /// Unreadable values fall back to the defaults.
    public init(from defaults: UserDefaults) {
        showsCompleted = defaults.bool(forKey: Keys.showsCompleted)
        let stored = defaults.stringArray(forKey: Keys.collapsed) ?? []
        collapsed = Set(stored.compactMap(ListSectionID.init(storageKey:)))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(showsCompleted, forKey: Keys.showsCompleted)
        defaults.set(collapsed.map(\.storageKey).sorted(), forKey: Keys.collapsed)
    }
}
