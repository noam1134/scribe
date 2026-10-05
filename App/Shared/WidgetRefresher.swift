import CoreData
import ScribeCore
import WidgetKit
#if os(iOS)
import UIKit
#endif

/// Keeps widgets current from the app (spec §4.3, §10.2): reloads their
/// timelines after every store change — the app's own saves, iCloud
/// imports, writes by the widget or intents — and records when the data was
/// last known to match iCloud, for the widgets' "Updated …" label (spec §18).
@MainActor
final class WidgetRefresher {
    private var observers: [NSObjectProtocol] = []
    private var pendingReload: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        // Posted after every save and import on the store.
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.succeeded, let end = event.endDate else { return }
            FreshnessStamp.record(end)
        })
        #if os(iOS)
        // In front, the app gets iCloud's pushes; from here on it may not
        // (spec §18), so the data is current as of now.
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                FreshnessStamp.record()
                self?.reloadNow()
                BackgroundRefresh.schedule()
            }
        })
        #endif
    }

    /// Saves and imports come in bursts; reload once they settle.
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            reloadNow()
        }
    }

    private func reloadNow() {
        pendingReload?.cancel()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
