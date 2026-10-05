public enum ItemKind: String, Codable, Sendable, CaseIterable {
    /// Something to do; has a checkbox.
    case task
    /// Something to remember; no checkbox, never done, never overdue.
    case memo
}
