import AppIntents
import Foundation
import ScribeCore
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "intents")

/// The widget checkbox (spec §10.1). Runs in the widget extension, writing
/// the shared file directly; the app exports the change to iCloud on its
/// next launch or activation (spec §4.3, §12).
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    /// It takes a raw item id, so it isn't offered in Shortcuts.
    static let isDiscoverable = false

    @Parameter(title: "Item ID")
    var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        log.info("CompleteTaskIntent runs in \(ProcessInfo.processInfo.processName, privacy: .public)")
        guard let id = UUID(uuidString: itemID) else { return .result() }
        let store = try SharedStore.openForIntent()
        do {
            try store.setDone(id, true)
        } catch StoreError.itemNotFound {
            // Deleted on another device; the reload below drops the row.
        } catch let error as StoreError {
            throw IntentError.store(error)
        }
        await StoreChanged.notify()
        return .result()
    }
}
