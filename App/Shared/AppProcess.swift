import CoreData
import ScribeCore
import os
#if os(iOS)
import UIKit
#endif

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "process")

/// Services of the app process, started once when its store first opens —
/// by the screens, Siri, a widget tick or background refresh alike, so a
/// process launched in the background has them too.
@MainActor
enum AppProcess {
    private static var syncRefresher: SyncRefresher?
    private static var changeRelay: StoreChangeRelay?

    static func start(_ store: SwiftDataItemStore) {
        guard syncRefresher == nil else { return }
        syncRefresher = SyncRefresher(store: store)
        changeRelay = StoreChangeRelay()
        // From the store's first CloudKit event on, for Settings' "Last synced".
        SyncMonitor.shared.start()
        // Writes outside the screens (Siri, a widget tick, background
        // refresh) re-plan before they return. The scheduler serializes and
        // coalesces passes, so overlapping calls are safe.
        StoreChanged.observe { await NotificationCoordinator.shared.rescheduleNow() }
        // Collects what Claude queued and publishes what's coming up.
        MailboxSync.shared.start(store: store)
        log.info("App services started")
    }
}

extension SharedStore {
    static func processDidOpen(_ store: SwiftDataItemStore) {
        AppProcess.start(store)
    }
}

/// Turns the store's own notifications — the app's saves, iCloud imports,
/// writes by the widget or intents — into one debounced widget reload, and
/// records when the data was last known to match iCloud, for the widgets'
/// "Updated …" label (spec §18). Notifications follow those changes by
/// watching the store themselves.
@MainActor
final class StoreChangeRelay {
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        // Posted after every save and import on the store.
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.succeeded, let end = event.endDate else { return }
            MainActor.assumeIsolated {
                FreshnessStamp.record(end)
                // Even an import with no changes moves "Updated …" forward.
                self?.scheduleReload()
            }
        })
        #if os(iOS)
        // In front, the app gets iCloud's pushes; from here on it may not
        // (spec §18), so the data is current as of now.
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                FreshnessStamp.record()
                self?.notifyBeforeSuspension()
                BackgroundRefresh.schedule()
            }
        })
        #endif
    }

    /// Saves and imports come in bursts; reload once they settle.
    private func scheduleReload() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            StoreChanged.reloadWidgets()
        }
    }

    #if os(iOS)
    /// Widgets drop their "Updated …" label and pending notifications are
    /// brought up to date — inside a background task, so the app isn't
    /// suspended halfway.
    private func notifyBeforeSuspension() {
        pending?.cancel() // notify() reloads the widgets too
        let assertion = BackgroundAssertion(name: "Scribe: store changed")
        Task {
            await StoreChanged.notify()
            assertion.end()
        }
    }
    #endif
}

#if os(iOS)
/// A `beginBackgroundTask` that ends exactly once: when the work finishes or
/// when iOS says time is up.
@MainActor
private final class BackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
