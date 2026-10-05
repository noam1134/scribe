enum ItemOrdering {
    /// Dated before undated; by due date (untimed first within a day);
    /// ties broken by creation time, oldest first.
    static func byDue(_ a: ItemSnapshot, _ b: ItemSnapshot) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.createdAt < b.createdAt
        }
    }

    /// Order inside a category or the Inbox: dated items by due date,
    /// then undated items newest first.
    static func list(_ a: ItemSnapshot, _ b: ItemSnapshot) -> Bool {
        if a.due == nil && b.due == nil { return a.createdAt > b.createdAt }
        return byDue(a, b)
    }
}
