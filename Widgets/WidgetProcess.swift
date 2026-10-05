import ScribeCore

extension SharedStore {
    /// The widget extension starts nothing when its store opens: it writes
    /// only from intents, which call `StoreChanged.notify()` themselves.
    static func processDidOpen(_ store: SwiftDataItemStore) {}
}
