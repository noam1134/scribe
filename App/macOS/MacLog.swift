import CoreData
import os

/// Unified-log channels for what only a signed run on the author's Mac can
/// show (spec §18). Read them with
/// `log stream --level info --predicate 'subsystem == "com.noamchuri.scribe"'`.
enum MacLog {
    static let push = Logger(subsystem: "com.noamchuri.scribe", category: "push")
    static let sync = Logger(subsystem: "com.noamchuri.scribe", category: "sync")
    static let hotkey = Logger(subsystem: "com.noamchuri.scribe", category: "hotkey")
}

/// Logs every CloudKit setup/import/export as it starts and ends, so a
/// signed run shows whether imports follow pushes or only app activation.
/// Lives as long as the app.
@MainActor
final class SyncEventLog {
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event else { return }
            let type = switch event.type {
            case .setup: "setup"
            case .import: "import"
            case .export: "export"
            @unknown default: "event \(event.type.rawValue)"
            }
            if event.endDate == nil {
                MacLog.sync.info("CloudKit \(type, privacy: .public) started")
            } else if event.succeeded {
                MacLog.sync.info("CloudKit \(type, privacy: .public) succeeded")
            } else {
                let reason = event.error.map { String(describing: $0) } ?? "no error"
                MacLog.sync.error("CloudKit \(type, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }
}
