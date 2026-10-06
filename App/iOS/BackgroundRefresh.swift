import BackgroundTasks
import CoreData
import ScribeCore
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "background")

/// Background app refresh (spec §18): iOS doesn't wake the app for iCloud's
/// silent pushes, so widgets would show what the store held when the app
/// last ran. This asks iOS to run the app now and then. On a cold launch,
/// opening the store sets up iCloud mirroring, which imports; on a warm wake
/// there is no "import now" API, so the task only waits briefly in case one
/// is already running. Then it reloads the widgets. Whether iOS grants the
/// time and an import actually runs can only be seen on a device — the
/// widgets' "Updated …" label is the fallback.
enum BackgroundRefresh {
    /// Also listed in Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let identifier = "com.noamchuri.scribe.refresh"

    /// No earlier than this after the request; iOS picks the actual time.
    private static let interval: TimeInterval = 30 * 60
    /// Background tasks get about 30 seconds.
    private static let coldImportWait: Duration = .seconds(20)
    private static let warmImportWait: Duration = .seconds(5)

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
        let launch = SharedStore.isOpen ? "warm wake" : "cold launch"
        log.info("Background refresh started (\(launch, privacy: .public))")
        guard let store = try? SharedStore.open() else {
            log.error("Background refresh (\(launch, privacy: .public)): store failed to open")
            return
        }
        let imported = await ImportWaiter().wait(upTo: launch == "cold launch" ? coldImportWait : warmImportWait)
        if let imported { FreshnessStamp.record(imported) }
        log.info("Background refresh finished (\(launch, privacy: .public)); import \(imported == nil ? "not seen" : "succeeded", privacy: .public)")
        store.refresh()
        // Items Claude queued, and a fresh "what's coming up" for it.
        await MailboxSync.shared.syncNow()
        await StoreChanged.notify()
    }
}

/// Waits for the next successful iCloud import to finish, the timeout, or
/// the system cancelling the background task — whichever comes first.
@MainActor
private final class ImportWaiter {
    private var observer: NSObjectProtocol?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<Date?, Never>?

    /// The import's end time, or nil if none finished in time.
    func wait(upTo limit: Duration) async -> Date? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { return finish(nil) }
                observer = NotificationCenter.default.addObserver(
                    forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
                ) { [weak self] note in
                    let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                          event.type == .import, event.succeeded, let end = event.endDate else { return }
                    MainActor.assumeIsolated { self?.finish(end) }
                }
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: limit)
                    self?.finish(nil)
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(nil) }
        }
    }

    private func finish(_ result: Date?) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation.resume(returning: result)
    }
}
