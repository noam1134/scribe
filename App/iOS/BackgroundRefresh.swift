import BackgroundTasks
import CoreData
import ScribeCore
import WidgetKit
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "background")

/// Background app refresh (spec §18): iOS doesn't wake the app for iCloud's
/// silent pushes, so widgets would show what the store held when the app
/// last ran. This asks iOS to run the app now and then; opening the store
/// starts iCloud's import, the task waits briefly for it, then reloads the
/// widgets. Whether iOS grants the time and the import actually runs can
/// only be seen on a device — the widgets' "Updated …" label is the fallback.
enum BackgroundRefresh {
    /// Also listed in Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let identifier = "com.noamchuri.scribe.refresh"

    /// No earlier than this after the request; iOS picks the actual time.
    private static let interval: TimeInterval = 30 * 60
    /// Background tasks get about 30 seconds.
    private static let importWait: Duration = .seconds(20)

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Couldn't schedule refresh: \(String(describing: error), privacy: .public)")
        }
    }

    @MainActor
    static func run() async {
        schedule()
        log.info("Background refresh started")
        guard let store = try? SharedStore.open() else {
            log.error("Background refresh: store failed to open")
            return
        }
        let imported = await ImportWaiter().wait(upTo: importWait)
        if let imported { FreshnessStamp.record(imported) }
        log.info("Background refresh finished; import \(imported == nil ? "not seen" : "succeeded", privacy: .public)")
        store.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Waits for the next successful iCloud import to finish, or gives up.
@MainActor
private final class ImportWaiter {
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<Date?, Never>?

    /// The import's end time, or nil if none finished in time.
    func wait(upTo timeout: Duration) async -> Date? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
            ) { [weak self] note in
                let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                      event.type == .import, event.succeeded, let end = event.endDate else { return }
                MainActor.assumeIsolated { self?.finish(end) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.finish(nil)
            }
        }
    }

    private func finish(_ result: Date?) {
        guard let continuation else { return }
        self.continuation = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation.resume(returning: result)
    }
}
