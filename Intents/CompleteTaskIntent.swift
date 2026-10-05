import AppIntents
import Foundation
import ScribeCore
import UserNotifications
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "intents")

/// The widget checkbox (spec §10.1).
///
/// On iPhone it runs in the app process (`LiveActivityIntent`, below): the
/// tick goes through the iCloud-syncing store, so it's exported at once, and
/// `StoreChanged.notify()` re-plans notifications. On the Mac (no
/// `LiveActivityIntent`) it runs in the widget extension: it writes the
/// shared file — the app exports and re-plans on its next activation — and
/// withdraws the task's own alert here.
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
        guard let id = UUID(uuidString: itemID) else {
            StoreChanged.reloadWidgets()
            return .result()
        }
        do {
            try SharedStore.openForIntent().setDone(id, true)
        } catch StoreError.itemNotFound {
            // Deleted on another device; the reload below drops the row.
        } catch {
            // Redraw anyway, so the row isn't left looking ticked.
            StoreChanged.reloadWidgets()
            throw (error as? StoreError).map(IntentError.store) ?? error
        }
        if !SharedStore.isApp {
            Self.withdrawAlert(for: id)
        }
        await StoreChanged.notify()
        return .result()
    }

    /// In the extension nothing re-plans notifications until the app runs,
    /// so take back the completed task's own alert (pending or delivered).
    private static func withdrawAlert(for itemID: UUID) {
        let identifier = PlannedNotification.identifier(forItem: itemID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

#if os(iOS)
/// Makes the system run the widget's checkbox in the app process, launched
/// in the background without opening it (checked in the simulator: after
/// the widget re-renders, ticks log "runs in Scribe").
extension CompleteTaskIntent: LiveActivityIntent {}
#endif
