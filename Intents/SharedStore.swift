import Foundation
import ScribeCore

/// The one store of this process (spec §4.3). The app opens it with iCloud
/// sync; the widget extension (timelines, the checkbox, configuration
/// lists) opens the same App Group file without. App Intents that run inside
/// the app — Siri, Shortcuts, the Control — get the app's store, so their
/// writes reach iCloud at once and open screens see them.
@MainActor
enum SharedStore {
    private static var store: SwiftDataItemStore?

    /// The app bundle ends in ".app"; the widget extension in ".appex".
    static let isApp = Bundle.main.bundleURL.pathExtension == "app"

    /// UI tests launch with `-uiTesting`: a fresh in-memory store, no iCloud.
    static let isUITesting = CommandLine.arguments.contains("-uiTesting")

    /// Whether this process has opened its store yet — a background launch
    /// can tell a cold start from a warm wake.
    static var isOpen: Bool { store != nil }

    /// Opens the store on first use, whoever asks first (the app's screens,
    /// Siri, a widget tick, background refresh), and starts the process's
    /// services (`processDidOpen`, defined per target). A failure isn't
    /// remembered, so the next call (Retry, the next timeline) tries again.
    static func open() throws -> SwiftDataItemStore {
        if let store { return store }
        let container = isUITesting
            ? try StoreFactory.inMemory()
            : try StoreFactory.shared(syncsWithCloudKit: isApp)
        let opened = SwiftDataItemStore(container: container)
        store = opened
        processDidOpen(opened)
        return opened
    }
}
